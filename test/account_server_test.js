const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'geonexo-account-test-'));
Object.assign(process.env, {
  DB_PATH: path.join(directory, 'app.db'), SEED_SAMPLE_DATA: 'false',
  ENABLE_APP_AUTH: 'true', ADMIN_EMAIL: 'admin@example.test', ADMIN_PASSWORD: 'test-password',
  ADMIN_COOKIE_SECRET: 'isolated-account-test-secret', APP_AUTH_TOKEN: 'isolated-mobile-token',
  PWA_DIR: directory, VAPID_PUBLIC_KEY: '', VAPID_PRIVATE_KEY: '', VAPID_SUBJECT: '',
});
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

async function call(method, route, { body, token, cookie } = {}) {
  const response = await fetch(`${origin}${route}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(cookie ? { cookie } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const text = await response.text();
  let data = null;
  try { data = JSON.parse(text); } catch (_) { /* not JSON */ }
  return { status: response.status, data, text, cookie: response.headers.get('set-cookie') };
}
const native = (email, password = 'senha-segura') => ({ email, password, client: 'native' });

test('the same account and profile work from the APK (token) and the PWA (cookie)', async () => {
  const created = await call('POST', '/api/account/register', { body: native('Giu@Example.test') });
  assert.equal(created.status, 201);
  assert.equal(created.data.user.email, 'giu@example.test');
  const { token } = created.data;
  const profile = { name: 'Giuseppe', birthDate: '2004-01-31', sex: 'masculino', city: 'Cuiabá', occupations: ['estudante'] };
  const saved = await call('PUT', '/api/account/profile', { token, body: { profile, revision: 0 } });
  assert.deepEqual(saved.data, { profile, revision: 1 });

  const web = await call('POST', '/api/account/login', { body: { email: 'giu@example.test', password: 'senha-segura' } });
  assert.equal(web.status, 200);
  assert.equal(web.data.token, undefined);
  assert.match(web.cookie, /HttpOnly/);
  assert.match(web.cookie, /SameSite=Lax/);
  const cookie = web.cookie.split(';')[0];
  assert.deepEqual((await call('GET', '/api/account/profile', { cookie })).data, { profile, revision: 1 });
  assert.equal((await call('GET', '/api/location/offline-bundle', { cookie })).status, 200);
  assert.equal((await call('GET', '/api/admin/catalog', { cookie })).status, 401);
  assert.equal((await call('GET', '/api/admin/catalog', { token })).status, 401);

  await call('POST', '/api/account/logout', { cookie });
  assert.equal((await call('GET', '/api/account/profile', { cookie })).status, 401);
  assert.equal((await call('GET', '/api/account/session', { cookie })).data.user, null);
  assert.equal((await call('GET', '/api/account/profile', { token })).status, 200);
});

test('profiles are private: guests and the shared app token cannot read them', async () => {
  assert.equal((await call('GET', '/api/account/profile')).status, 401);
  assert.equal((await call('GET', '/api/account/profile', { token: 'isolated-mobile-token' })).status, 401);
  const guest = await call('POST', '/api/app/auth/guest');
  assert.equal((await call('GET', '/api/account/profile', { cookie: guest.cookie.split(';')[0] })).status, 401);

  const other = (await call('POST', '/api/account/register', { body: native('outra@example.test') })).data.token;
  assert.deepEqual((await call('GET', '/api/account/profile', { token: other })).data, { profile: {}, revision: 0 });
});

test('every field is optional, invalid values are rejected and stale writes conflict', async () => {
  const { token } = (await call('POST', '/api/account/register', { body: native('campos@example.test') })).data;
  const put = (profile, revision) => call('PUT', '/api/account/profile', { token, body: { profile, revision } });
  for (const bad of [
    { birthDate: '2025-02-30' }, { birthDate: '2999-01-01' }, { birthDate: 22 }, { sex: 'x' },
    { occupations: ['astronauta'] }, { occupations: 'estudante' }, { name: 'a'.repeat(81) }, { name: 5 }, { cpf: '1' }, [], null,
  ]) assert.equal((await put(bad, 0)).status, 400, JSON.stringify(bad));
  assert.deepEqual((await put({}, 0)).data, { profile: {}, revision: 1 });
  assert.deepEqual((await put({ name: '  Ana  ', city: ' ' }, 1)).data, { profile: { name: 'Ana' }, revision: 2 });
  const stale = await put({ name: 'Velho' }, 1);
  assert.equal(stale.status, 409);
  assert.deepEqual(stale.data, { profile: { name: 'Ana' }, revision: 2 });
  assert.equal((await put({}, 2)).status, 200);
});

test('accounts: duplicates, weak passwords, admin e-mail and brute force are refused', async () => {
  const body = native('dup@example.test');
  assert.equal((await call('POST', '/api/account/register', { body })).status, 201);
  assert.equal((await call('POST', '/api/account/register', { body: native('DUP@example.test') })).status, 409);
  assert.equal((await call('POST', '/api/account/register', { body: native('admin@example.test') })).status, 409);
  assert.equal((await call('POST', '/api/account/register', { body: native('curta@example.test', '1234567') })).status, 400);
  assert.equal((await call('POST', '/api/account/register', { body: native('invalido') })).status, 400);
  const attempts = await Promise.all(Array.from({ length: 12 }, () =>
    call('POST', '/api/account/login', { body: native('dup@example.test', 'errada-123') })));
  assert.equal(attempts.filter((item) => item.status === 401).length, 10);
  assert.equal(attempts.filter((item) => item.status === 429).length, 2);
});

test('deleting the account removes profile and sessions; secrets are not stored in clear', async () => {
  const { token, user } = (await call('POST', '/api/account/register', { body: native('apagar@example.test') })).data;
  await call('PUT', '/api/account/profile', { token, body: { profile: { name: 'Apagar' }, revision: 0 } });
  const db = await getDb();
  const row = await db.get('SELECT * FROM app_users WHERE id = ?', [user.id]);
  assert.ok(!row.password_hash.includes('senha-segura'));
  assert.equal(await db.get('SELECT 1 FROM app_user_sessions WHERE token_hash = ?', [token]), undefined);

  assert.equal((await call('DELETE', '/api/account', { token, body: { password: 'errada' } })).status, 403);
  assert.equal((await call('DELETE', '/api/account', { token, body: { password: 'senha-segura' } })).status, 200);
  assert.equal((await call('GET', '/api/account/profile', { token })).status, 401);
  for (const table of ['user_profiles', 'app_user_sessions']) {
    assert.equal((await db.get(`SELECT COUNT(*) AS n FROM ${table} WHERE user_id = ?`, [user.id])).n, 0);
  }
});

test('public dashboard and open data never contain profile data', async () => {
  const { token } = (await call('POST', '/api/account/register', { body: native('segredo@example.test') })).data;
  await call('PUT', '/api/account/profile', { token, body: { profile: { name: 'NomeSecreto', city: 'CidadeSecreta' }, revision: 0 } });
  for (const route of ['/api/public/dashboard', ...['respostas', 'resultados', 'por-dia', 'locais'].flatMap(
    (name) => [`/api/public/export/${name}.csv`, `/api/public/export/${name}.json`])]) {
    const { status, text } = await call('GET', route);
    assert.equal(status, 200, route);
    assert.doesNotMatch(text, /NomeSecreto|CidadeSecreta|segredo@example/);
  }
});
