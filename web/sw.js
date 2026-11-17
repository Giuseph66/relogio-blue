// Replaced with content hashes by scripts/build_pwa.py after flutter build web.
const VERSION = '__GEONEXO_VERSION__';
const CACHE = `geonexo-shell-${VERSION}`;
const RESOURCES = __GEONEXO_RESOURCES__;
const base = self.registration.scope;
const absoluteResources = new Set(RESOURCES.map((path) => new URL(path, base).href));

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(
    RESOURCES.map((path) => new Request(new URL(path, base), { cache: 'reload' })),
  )));
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith('geonexo-shell-') && name !== CACHE) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('message', (event) => {
  if (event.data === 'ACTIVATE_UPDATE') self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  // API, other apps on this origin, map tiles and geocoding stay out of caches.
  if (!url.href.startsWith(base)) return;
  const isNavigation = event.request.mode === 'navigate';
  const key = isNavigation ? new URL('index.html', base).href : url.href;
  if (!isNavigation && !absoluteResources.has(key)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const cached = await cache.match(key);
    if (cached) return cached;
    return fetch(event.request);
  })());
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const app = windows.find((client) => client.url.startsWith(base));
    const recordId = event.notification.data?.recordId;
    if (app) {
      await app.focus();
      app.postMessage({ type: 'question.open', recordId });
      return;
    }
    const url = new URL(base);
    if (recordId) url.searchParams.set('question', recordId);
    return self.clients.openWindow(url.href);
  })());
});
