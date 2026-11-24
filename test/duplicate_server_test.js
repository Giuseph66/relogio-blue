const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'geonexo-duplicate-test-'));
Object.assign(process.env, {
  DB_PATH: path.join(directory, 'app.db'), SEED_SAMPLE_DATA: 'false',
  ENABLE_APP_AUTH: 'true', ADMIN_EMAIL: 'admin@example.test', ADMIN_PASSWORD: 'test-password',
  ADMIN_COOKIE_SECRET: 'isolated-duplicate-test-secret', APP_AUTH_TOKEN: 'isolated-mobile-token',
  PWA_DIR: directory, VAPID_PUBLIC_KEY: '', VAPID_PRIVATE_KEY: '', VAPID_SUBJECT: '',
});
// A database from before the rule, with answers that share one device id.
const sqlite3 = require('../server/node_modules/sqlite3');
const { schema } = require('../server/src/db/schema');
const { createApp } = require('../server/src/app');
const { getDb } = require('../server/src/db/connection');
const QUESTION = 'qst_0123456789abcdef';
const OTHER = 'qst_fedcba9876543210';
let server;
let origin;
before(async () => {
  const old = new sqlite3.Database(process.env.DB_PATH);
  await new Promise((resolve, reject) => old.exec(`${schema}
    INSERT INTO questions (id, prompt, created_at, updated_at) VALUES ('${QUESTION}','p','x','x'),('${OTHER}','p','x','x');
    INSERT INTO devices (id, status, created_at, updated_at) VALUES ('mobile-app','active','x','x');
    INSERT INTO responses (id, device_id, question_id, raw_payload_json, received_at)
      VALUES ('a','mobile-app','${QUESTION}','{}','x'),('b','mobile-app','${QUESTION}','{}','x');`,
  (error) => (error ? reject(error) : old.close(resolve))));
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

const phone = (n) => `android-${String(n).repeat(64).slice(0, 64)}`;
let next = 0;
async function post(body, headers = {}) {
  const response = await fetch(`${origin}/api/responses`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify({ questionId: QUESTION.slice(0, 10), answerId: 'A', responseId: `r${next++}`, ...body }),
  });
  return { status: response.status, data: await response.json(), cookie: response.headers.get('set-cookie') };
}
const app = { Authorization: 'Bearer isolated-mobile-token' };
const count = async () => (await (await getDb()).get('SELECT COUNT(*) AS n FROM responses')).n;

test('one phone answers each question once, whatever it changes in the request', async () => {
  const start = await count();
  assert.equal((await post({ deviceId: phone(1) }, app)).status, 201);
  assert.equal((await post({ deviceId: phone(1) }, app)).status, 409);
  assert.equal((await post({ deviceId: phone(1), answerId: 'B', submittedAt: 'x', locationId: 'y' }, app)).status, 409);
  assert.equal((await post({ deviceId: phone(1), questionId: QUESTION }, app)).status, 409);
  assert.equal((await post({ deviceId: phone(1), responseId: undefined }, app)).status, 409);
  assert.equal((await post({ deviceId: phone(1), questionId: 'qst_01' }, app)).status, 409);
  assert.equal((await post({ deviceId: phone(2) }, app)).status, 201);
  const total = await (await getDb()).get('SELECT COUNT(*) AS n FROM responses WHERE question_id = ?', [QUESTION]);
  assert.equal(total.n, 2 + 2);
  assert.equal(await count() - start, 2);
});

test('resending the same answer after a lost reply is harmless', async () => {
  const body = { deviceId: phone(3), responseId: 'lost-reply' };
  assert.equal((await post(body, app)).status, 201);
  const again = await post(body, app);
  assert.equal(again.status, 200);
  assert.equal(again.data.created, false);
});

test('simultaneous attempts store exactly one answer', async () => {
  const different = await Promise.all(Array.from({ length: 10 }, () => post({ deviceId: phone(4) }, app)));
  assert.equal(different.filter((r) => r.status === 201).length, 1);
  assert.equal(different.filter((r) => r.status === 409).length, 9);
  const same = await Promise.all(Array.from({ length: 10 }, () => post({ deviceId: phone(5), responseId: 'same' }, app)));
  assert.equal(same.filter((r) => r.status === 201).length, 1);
  assert.equal(same.filter((r) => r.status === 200).length, 9);
});

test('shared, missing or made-up device ids and unknown questions are refused', async () => {
  for (const deviceId of ['mobile-app', undefined, '', 'android-1', `${phone(6)}x`, 5]) {
    assert.equal((await post({ deviceId }, app)).status, 426, String(deviceId));
  }
  assert.equal((await post({ deviceId: phone(6), questionId: 'nope' }, app)).status, 410);
  assert.equal((await post({ deviceId: phone(6) })).status, 401);
});

test('a browser is recognized by its HttpOnly cookie, not by what it claims', async () => {
  const guest = await fetch(`${origin}/api/app/auth/guest`, { method: 'POST' });
  const session = guest.headers.get('set-cookie').split(';')[0];
  // A browser tab is refused, and nothing is stored.
  const start = await count();
  assert.equal((await post({ deviceId: phone(7) }, { cookie: session })).status, 403);
  assert.equal((await post({}, { cookie: session, 'x-geonexo-app': 'browser' })).status, 403);
  assert.equal(await count(), start);
  const pwa = { 'x-geonexo-app': 'pwa' };
  const first = await post({ deviceId: phone(7) }, { ...pwa, cookie: session });
  assert.equal(first.status, 201);
  assert.match(first.cookie, /geonexo_device=[0-9a-f]{32};.*HttpOnly/);
  const cookie = `${session}; ${first.cookie.split(';')[0]}`;
  assert.equal((await post({ deviceId: phone(8) }, { ...pwa, cookie })).status, 409);
  assert.equal((await post({ deviceId: phone(8), questionId: OTHER.slice(0, 10) }, { ...pwa, cookie })).status, 201);
});

test('only an administrator verified by the server may answer repeatedly', async () => {
  const login = (body) => fetch(`${origin}/api/admin/auth/login`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'admin@example.test', password: 'test-password', ...body }),
  });
  const { token } = await (await login({ client: 'native' })).json();
  const native = { ...app, 'x-admin-session': token };
  assert.equal((await post({ deviceId: phone(1) }, native)).status, 201);
  assert.equal((await post({ deviceId: phone(1) }, native)).status, 201);
  const web = await login({});
  assert.equal((await web.clone().json()).token, undefined);
  const cookie = web.headers.get('set-cookie').split(';')[0];
  assert.equal((await post({}, { cookie })).status, 201);
  assert.equal((await post({}, { cookie })).status, 201);

  // Claims, forged and participant sessions do not count.
  assert.equal((await post({ deviceId: phone(1), admin: true, isAdmin: true }, app)).status, 409);
  assert.equal((await post({ deviceId: phone(1) }, { ...app, 'x-admin-session': `${token}x` })).status, 401);
  const account = await (await fetch(`${origin}/api/account/register`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'p@example.test', password: 'senha-segura', client: 'native' }),
  })).json();
  assert.equal((await post({ deviceId: phone(1) }, { ...app, 'x-admin-session': account.token })).status, 401);
  assert.equal((await post({ deviceId: phone(1) }, { Authorization: `Bearer ${account.token}` })).status, 409);
});

test('device identity is not stored with the answers', async () => {
  const rows = await (await getDb()).all('SELECT * FROM responses');
  const devices = await (await getDb()).all('SELECT * FROM devices');
  assert.doesNotMatch(JSON.stringify([rows, devices]), /android-|web-[0-9a-f]{32}/);
});

test('administrator password guessing is limited', async () => {
  const tries = [];
  for (let i = 0; i < 11; i += 1) {
    tries.push((await fetch(`${origin}/api/admin/auth/login`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'ADMIN@example.test', password: 'x' }),
    })).status);
  }
  assert.deepEqual(tries, [...Array(10).fill(401), 429]);
});
