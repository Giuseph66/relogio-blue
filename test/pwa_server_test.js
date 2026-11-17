const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'geonexo-server-test-'));
Object.assign(process.env, {
  DB_PATH: path.join(directory, 'app.db'), SEED_SAMPLE_DATA: 'false',
  ENABLE_APP_AUTH: 'true', ADMIN_EMAIL: 'test@example.test', ADMIN_PASSWORD: 'test-password',
  ADMIN_COOKIE_SECRET: 'isolated-pwa-test-secret', APP_AUTH_TOKEN: 'isolated-mobile-token',
  PWA_DIR: directory,
  VAPID_PUBLIC_KEY: '', VAPID_PRIVATE_KEY: '', VAPID_SUBJECT: '',
});
fs.writeFileSync(path.join(directory, 'index.html'), '<!doctype html><title>PWA test</title>');
const { createApp } = require('../server/src/app');
const { getDb } = require('../server/src/db/connection');
let server;
let origin;
before(async () => {
  await getDb();
  server = createApp().listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  origin = `http://127.0.0.1:${server.address().port}`;
});
after(async () => {
  await new Promise((resolve) => server.close(resolve));
  await (await getDb()).close();
  fs.rmSync(directory, { recursive: true, force: true });
});

test('PWA participant cookie authorizes app APIs without granting admin access', async () => {
  assert.equal((await fetch(`${origin}/api/location/offline-bundle`)).status, 401);
  const guest = await fetch(`${origin}/api/app/auth/guest`, { method: 'POST' });
  assert.equal(guest.status, 200);
  const cookie = guest.headers.get('set-cookie').split(';')[0];
  assert.match(guest.headers.get('set-cookie'), /HttpOnly/);
  assert.match(guest.headers.get('set-cookie'), /SameSite=Lax/);
  assert.equal((await fetch(`${origin}/api/location/offline-bundle`, { headers: { cookie } })).status, 200);
  assert.equal((await fetch(`${origin}/api/admin/catalog`, { headers: { cookie } })).status, 401);
  const copiedGuestCookie = `rb_admin_session=${cookie.slice(cookie.indexOf('=') + 1)}`;
  assert.equal((await fetch(`${origin}/api/admin/catalog`, { headers: { cookie: copiedGuestCookie } })).status, 401);
  assert.equal((await fetch(`${origin}/api/admin/push/status`, { headers: { 'x-appengine-cron': 'true' } })).status, 401);
  const tampered = cookie.slice(0, -1) + (cookie.endsWith('a') ? 'b' : 'a');
  assert.equal((await fetch(`${origin}/api/location/offline-bundle`, { headers: { cookie: tampered } })).status, 401);
});

test('Native mobile bearer token continues to authorize app APIs', async () => {
  const response = await fetch(`${origin}/api/location/offline-bundle`, {
    headers: { Authorization: 'Bearer isolated-mobile-token' },
  });
  assert.equal(response.status, 200);
});

test('server remains usable without VAPID and push reports disabled clearly', async () => {
  const config = await fetch(`${origin}/api/push/config`);
  assert.deepEqual(await config.json(), { enabled: false, publicKey: null });
  assert.equal((await fetch(`${origin}/api/push/test`, {
    method: 'POST', headers: { Authorization: 'Bearer isolated-mobile-token' },
  })).status, 503);
});

test('Admin cookie authorizes the PWA and invalid coordinates never reach geocoder', async () => {
  const login = await fetch(`${origin}/api/admin/auth/login`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'test@example.test', password: 'test-password' }),
  });
  assert.equal(login.status, 200);
  const cookie = login.headers.get('set-cookie').split(';')[0];
  assert.equal((await fetch(`${origin}/api/location/offline-bundle`, { headers: { cookie } })).status, 200);
  assert.equal((await fetch(`${origin}/api/geocoding?lat=999&lon=0`, { headers: { cookie } })).status, 400);
  assert.equal((await fetch(`${origin}/api/geocoding?q=ab`, { headers: { cookie } })).status, 400);
});

test('SPA routes serve HTML; missing script assets return 404', async () => {
  const route = await fetch(`${origin}/app/history`);
  assert.equal(route.status, 200);
  assert.match(await route.text(), /PWA test/);
  assert.match(route.headers.get('cache-control'), /no-cache/);
  assert.equal((await fetch(`${origin}/app/missing.js`)).status, 404);
});
