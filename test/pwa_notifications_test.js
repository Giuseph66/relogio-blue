const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../web/geonexo.js'), 'utf8');

function browser({ ios = false, installed = true, permission = 'granted', registration } = {}) {
  const notifications = [];
  let requests = 0;
  const navigator = {
    userAgent: ios ? 'iPhone' : 'Chrome', platform: ios ? 'iPhone' : 'Linux',
    standalone: installed, maxTouchPoints: 1,
    serviceWorker: {
      addEventListener() {},
      async getRegistration() { return registration || {
        active: {}, async showNotification(title, options) { notifications.push({ title, ...options }); },
        async getNotifications({ tag }) { return notifications.filter(n => n.tag === tag).map(n => ({ close() { n.closed = true; } })); },
      }; },
    },
  };
  const Notification = { permission, requestPermission() { requests++; return Promise.resolve(permission); } };
  const window = {
    navigator, Notification, isSecureContext: true,
    matchMedia: () => ({ matches: installed }), addEventListener() {},
  };
  vm.runInNewContext(source, {
    window, navigator, Notification, URL, Uint8Array, Promise, Map,
    document: { baseURI: 'https://example.test/app/', addEventListener() {} },
  });
  return { bridge: window.geonexo, notifications, requests: () => requests };
}
async function call(bridge, method, data = {}) {
  return JSON.parse(await bridge.call(method, JSON.stringify(data)));
}

test('iPhone requires Home Screen installation before requesting permission', async () => {
  const env = browser({ ios: true, installed: false });
  assert.equal((await call(env.bridge, 'notifications.status')).value.needsInstallation, true);
  assert.equal((await call(env.bridge, 'notifications.request')).value, 'install-required');
  assert.equal(env.requests(), 0);
});

test('installed iPhone requests notification permission directly in the click call', async () => {
  const env = browser({ ios: true });
  const result = env.bridge.call('notifications.request', '{}');
  assert.equal(env.requests(), 1);
  assert.equal(JSON.parse(await result).value, 'granted');
});

test('notification delivery is awaited and carries the question record', async () => {
  let deliver;
  const env = browser({ registration: { active: {}, showNotification() { return new Promise(resolve => { deliver = resolve; }); } } });
  let complete = false;
  const request = call(env.bridge, 'notify', { title: 'Campus', body: 'Como está?', recordId: 'record-1' }).then(r => { complete = true; return r; });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(complete, false);
  deliver();
  assert.equal((await request).value, true);
  const real = browser();
  await call(real.bridge, 'notify', { title: 'Campus', body: 'Como está?', recordId: 'record-1', tag: 'q1' });
  assert.equal(real.notifications[0].data.recordId, 'record-1');
  assert.equal(real.notifications[0].icon, 'https://example.test/app/icons/Icon-192.png');
});

test('denied permission does not report a notification as sent', async () => {
  const env = browser({ permission: 'denied' });
  assert.equal((await call(env.bridge, 'notify', { title: 'Campus' })).value, false);
  assert.equal(env.notifications.length, 0);
});

test('delivery failure reaches the app instead of disappearing silently', async () => {
  const env = browser({ registration: { active: {}, async showNotification() { throw new Error('delivery failed'); } } });
  let event;
  env.bridge.listen(raw => { event = JSON.parse(raw); });
  assert.equal((await call(env.bridge, 'notify', { title: 'Campus' })).ok, false);
  assert.equal(event.type, 'notification.error');
});

test('answering closes only the corresponding notification', async () => {
  const env = browser();
  await call(env.bridge, 'notify', { title: 'First', tag: 'q1' });
  await call(env.bridge, 'notify', { title: 'Second', tag: 'q2' });
  await call(env.bridge, 'notify.cancel', { tag: 'q1' });
  assert.equal(env.notifications[0].closed, true);
  assert.equal(env.notifications[1].closed, undefined);
});

function worker(clients) {
  const handlers = {};
  const source = fs.readFileSync(path.join(__dirname, '../web/sw.js'), 'utf8').replace('__GEONEXO_RESOURCES__', '[]');
  vm.runInNewContext(source, { URL, Set, self: {
    registration: { scope: 'https://example.test/app/' }, clients,
    addEventListener(type, callback) { handlers[type] = callback; },
  } });
  return handlers.notificationclick;
}

test('tapping a visit notification focuses the app and opens the right question', async () => {
  let focused = false;
  let message;
  const click = worker({ async matchAll() { return [{ url: 'https://example.test/app/', async focus() { focused = true; }, postMessage(data) { message = data; } }]; } });
  let pending;
  click({ notification: { data: { recordId: 'record-1' }, close() {} }, waitUntil(p) { pending = p; } });
  await pending;
  assert.equal(focused, true);
  assert.equal(message.recordId, 'record-1');
});

test('notification tap starts a closed app with its question reference', async () => {
  let url;
  const click = worker({ async matchAll() { return []; }, async openWindow(value) { url = value; } });
  let pending;
  click({ notification: { data: { recordId: 'record-2' }, close() {} }, waitUntil(p) { pending = p; } });
  await pending;
  assert.equal(url, 'https://example.test/app/?question=record-2');
});

function pushBrowser({ failSave = false, failDelete = false } = {}) {
  const requests = [];
  const stored = new Map();
  let subscribed = null;
  let creates = 0;
  let removes = 0;
  let publicKey = Buffer.alloc(65, 4).toString('base64url');
  const manager = {
    async getSubscription() { return subscribed; },
    async subscribe(options) {
      assert.equal(options.userVisibleOnly, true);
      assert.equal(options.applicationServerKey.length, 65);
      creates++;
      subscribed = {
        options: { applicationServerKey: options.applicationServerKey.buffer },
        toJSON() { return { endpoint: 'https://web.push.apple.com/test', keys: {} }; },
        async unsubscribe() { subscribed = null; removes++; return true; },
      };
      return subscribed;
    },
  };
  const navigator = { userAgent: 'iPhone', standalone: true, serviceWorker: {
    addEventListener() {}, async getRegistration() { return { active: {}, pushManager: manager }; },
  } };
  const window = { isSecureContext: true, Notification: {}, PushManager: {},
    matchMedia: () => ({ matches: true }), addEventListener() {},
  };
  vm.runInNewContext(source, {
    window, navigator, URL, Uint8Array, Map, Promise,
    Notification: { permission: 'granted' },
    crypto: require('node:crypto').webcrypto,
    atob: value => Buffer.from(value, 'base64').toString('binary'),
    localStorage: { getItem: key => stored.get(key), setItem: (key, value) => stored.set(key, value) },
    document: { baseURI: 'https://example.test/app/', addEventListener() {} },
    fetch: async (url, options) => {
      requests.push({ url, options });
      const failed = url.endsWith('/subscription') &&
        ((failSave && options.method === 'POST') || (failDelete && options.method === 'DELETE'));
      return { ok: !failed, async json() {
        return url.endsWith('/config') ? { enabled: true, publicKey } : failed ? { error: 'Servidor indisponível' } : {};
      } };
    },
  });
  return { bridge: window.geonexo, requests, creates: () => creates, removes: () => removes,
    rotateKey() { publicKey = Buffer.alloc(65, 5).toString('base64url'); },
  };
}

test('push activation enrolls with a stable installation token and renews without creating duplicates', async () => {
  const env = pushBrowser();
  assert.equal((await call(env.bridge, 'push.status')).value.subscribed, false);
  assert.equal((await call(env.bridge, 'push.enable')).value.subscribed, true);
  assert.equal((await call(env.bridge, 'push.status')).value.subscribed, true);
  assert.equal(env.creates(), 1);
  const saves = env.requests.filter(r => r.options.method === 'POST');
  const tokens = saves.map(r => JSON.parse(r.options.body).token);
  assert.match(tokens[0], /^[a-f0-9]{64}$/);
  assert.equal(tokens[0], tokens[1]);
});

test('failed server enrollment is reported instead of claiming push activation succeeded', async () => {
  const env = pushBrowser({ failSave: true });
  assert.equal((await call(env.bridge, 'push.enable')).ok, false);
});

test('a changed VAPID key requires renewal and replaces the old browser subscription', async () => {
  const env = pushBrowser();
  await call(env.bridge, 'push.enable');
  env.rotateKey();
  const status = (await call(env.bridge, 'push.status')).value;
  assert.equal(status.subscribed, false);
  assert.equal(status.hasSubscription, true);
  assert.equal((await call(env.bridge, 'push.enable')).value.subscribed, true);
  assert.equal(env.creates(), 2);
  assert.equal(env.removes(), 1);
});

test('disabling push unsubscribes in the browser even when the server cannot be reached', async () => {
  const env = pushBrowser({ failDelete: true });
  await call(env.bridge, 'push.enable');
  assert.equal((await call(env.bridge, 'push.disable')).ok, false);
  assert.equal(env.removes(), 1);
});

test('service worker displays remote pushes without an open window and handles malformed payloads', async () => {
  const handlers = {};
  const notices = [];
  const workerSource = fs.readFileSync(path.join(__dirname, '../web/sw.js'), 'utf8').replace('__GEONEXO_RESOURCES__', '[]');
  vm.runInNewContext(workerSource, { URL, Set, self: {
    registration: { scope: 'https://example.test/app/', async showNotification(title, options) { notices.push({ title, ...options }); } },
    addEventListener(type, callback) { handlers[type] = callback; },
  } });
  for (const json of [() => ({ title: 'Aula', body: 'Participe', tag: 'push-1' }), () => { throw new Error('invalid JSON'); }]) {
    let pending;
    handlers.push({ data: { json }, waitUntil(p) { pending = p; } });
    await pending;
  }
  assert.equal(notices[0].title, 'Aula');
  assert.equal(notices[0].body, 'Participe');
  assert.equal(notices[0].icon, 'https://example.test/app/icons/Icon-192.png');
  assert.equal(notices[1].title, 'GeoNexo');
  assert.match(notices[1].body, /novo aviso/);
});
