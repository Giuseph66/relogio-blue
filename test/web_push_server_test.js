const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const webpush = require('../server/node_modules/web-push');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'geonexo-push-test-'));
const vapid = webpush.generateVAPIDKeys();
Object.assign(process.env, {
  DB_PATH: path.join(directory, 'app.db'), SEED_SAMPLE_DATA: 'false', ENABLE_APP_AUTH: 'true',
  ADMIN_EMAIL: 'push@example.test', ADMIN_PASSWORD: 'push-test-password',
  ADMIN_COOKIE_SECRET: crypto.randomBytes(32).toString('hex'),
  VAPID_PUBLIC_KEY: vapid.publicKey, VAPID_PRIVATE_KEY: vapid.privateKey,
  VAPID_SUBJECT: 'mailto:push@example.test',
});
const { createApp } = require('../server/src/app');
const { getDb } = require('../server/src/db/connection');
let server, origin, guestCookie, adminCookie;
let transport = async () => {};
const sent = [];
const originalSend = webpush.sendNotification;
webpush.sendNotification = async (subscription, payload, options) => {
  // Exercise actual encryption and VAPID signing without contacting a real provider.
  const request = webpush.generateRequestDetails(subscription, payload, options);
  assert.equal(request.headers['Content-Encoding'], 'aes128gcm');
  assert(request.body.length > Buffer.byteLength(payload));
  assert.match(request.headers.Authorization, /^vapid /);
  sent.push({ endpoint: subscription.endpoint, payload: JSON.parse(payload) });
  return transport(subscription);
};
function subscription(id) {
  const key = crypto.createECDH('prime256v1'); key.generateKeys();
  return { endpoint: `https://fcm.googleapis.com/fcm/send/${id}`, keys: {
    p256dh: key.getPublicKey().toString('base64url'), auth: crypto.randomBytes(16).toString('base64url'),
  } };
}
const token1 = crypto.randomBytes(32).toString('hex');
const token2 = crypto.randomBytes(32).toString('hex');
const first = subscription('first');
const second = subscription('second');
async function api(route, { method = 'GET', cookie = guestCookie, body } = {}) {
  return fetch(origin + route, { method, headers: {
    'Content-Type': 'application/json', ...(cookie ? { cookie } : {}),
  }, ...(body ? { body: JSON.stringify(body) } : {}) });
}
before(async () => {
  server = createApp().listen(0);
  await new Promise(resolve => server.once('listening', resolve));
  origin = `http://127.0.0.1:${server.address().port}`;
  const guest = await api('/api/app/auth/guest', { method: 'POST' });
  guestCookie = guest.headers.get('set-cookie').split(';')[0];
  const admin = await api('/api/admin/auth/login', { method: 'POST', body: {
    email: 'push@example.test', password: 'push-test-password',
  } });
  adminCookie = admin.headers.get('set-cookie').split(';')[0];
});
after(async () => {
  webpush.sendNotification = originalSend;
  await new Promise(resolve => server.close(resolve));
  await (await getDb()).close();
  fs.rmSync(directory, { recursive: true, force: true });
});

test('only the public VAPID key is exposed and push APIs require authentication', async () => {
  const config = await (await api('/api/push/config', { cookie: null })).json();
  assert.deepEqual(config, { enabled: true, publicKey: vapid.publicKey });
  assert.equal((await api('/api/push/subscription', { method: 'POST', cookie: null })).status, 401);
  assert.equal((await api('/api/admin/push/send', { method: 'POST' })).status, 401);
});

test('subscription validates provider URLs and encryption keys before persistence', async () => {
  for (const endpoint of ['http://127.0.0.1/private', 'https://127.0.0.1/private',
    'https://fcm.googleapis.com.evil.test/send', 'https://user@fcm.googleapis.com/send',
    'https://fcm.googleapis.com:8443/send']) {
    assert.equal((await api('/api/push/subscription', { method: 'POST', body: {
      token: token1, subscription: { ...first, endpoint },
    } })).status, 400);
  }
  assert.equal((await api('/api/push/subscription', { method: 'POST', body: {
    token: token1, subscription: { ...first, keys: { ...first.keys, p256dh: 'A'.repeat(87) } },
  } })).status, 400);
  assert.equal((await (await getDb()).get('SELECT COUNT(*) AS total FROM push_subscriptions')).total, 0);
});

test('subscriptions persist in SQLite, renew without duplicates and remain installation-scoped', async () => {
  for (let i = 0; i < 2; i++) {
    assert.equal((await api('/api/push/subscription', { method: 'POST', body: { token: token1, subscription: first } })).status, 200);
  }
  assert.equal((await api('/api/push/subscription', { method: 'POST', body: { token: token2, subscription: first } })).status, 409);
  assert.equal((await api('/api/push/subscription', { method: 'POST', body: { token: token2, subscription: second } })).status, 200);
  const row = await (await getDb()).get('SELECT * FROM push_subscriptions WHERE endpoint = ?', first.endpoint);
  assert.notEqual(row.id, token1);
  assert.equal(JSON.parse(row.subscription_json).keys.p256dh, first.keys.p256dh);
  assert.equal((await (await api('/api/admin/push/status', { cookie: adminCookie })).json()).subscriptions, 2);
});

test('individual test uses the real Web Push protocol and cannot target another installation', async () => {
  assert.equal((await api('/api/push/test', { method: 'POST', body: { token: 'a'.repeat(64) } })).status, 404);
  const result = await api('/api/push/test', { method: 'POST', body: { token: token1 } });
  assert.deepEqual(await result.json(), { status: 'accepted' });
  assert.equal(sent.at(-1).endpoint, first.endpoint);
  assert.equal(sent.at(-1).payload.title, 'GeoNexo');
  assert.equal((await api('/api/push/test', { method: 'POST', body: { token: token1 } })).status, 429);
});

test('admin broadcast removes expired subscriptions and reports temporary failures without deleting them', async () => {
  transport = async sub => { throw Object.assign(new Error('provider rejected'), {
    statusCode: sub.endpoint === first.endpoint ? 410 : 503,
  }); };
  const result = await api('/api/admin/push/send', { method: 'POST', cookie: adminCookie,
    body: { title: 'Aula', body: 'Abra o GeoNexo para participar.' } });
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), { total: 2, accepted: 0, expired: 1, failed: 1 });
  assert.equal((await (await api('/api/admin/push/status', { cookie: adminCookie })).json()).subscriptions, 1);
  const bad = await api('/api/admin/push/send', { method: 'POST', cookie: adminCookie, body: { title: '', body: 'X' } });
  assert.equal(bad.status, 400);
});

test('unsubscribing one installation does not remove another', async () => {
  assert.equal((await api('/api/push/subscription', { method: 'DELETE', body: { token: token1 } })).status, 200);
  assert.equal((await (await api('/api/admin/push/status', { cookie: adminCookie })).json()).subscriptions, 1);
  assert.equal((await api('/api/push/subscription', { method: 'DELETE', body: { token: token2 } })).status, 200);
  assert.equal((await (await api('/api/admin/push/status', { cookie: adminCookie })).json()).subscriptions, 0);
});
