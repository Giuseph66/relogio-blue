{{flutter_js}}
{{flutter_build_config}}

// Keep the renderer on the same origin so the installed shell works offline.
_flutter.loader.load({
  config: { renderer: 'canvaskit', canvasKitBaseUrl: 'canvaskit/' },
});

if ('serviceWorker' in navigator && window.isSecureContext) {
  navigator.serviceWorker.register('sw.js', { scope: './', updateViaCache: 'none' })
    .then((registration) => {
      const announce = () => {
        if (registration.waiting && navigator.serviceWorker.controller) window.geonexo.notifyUpdate();
      };
      announce();
      registration.addEventListener('updatefound', () => {
        registration.installing?.addEventListener('statechange', announce);
      });
    })
    .catch((error) => console.warn('GeoNexo offline:', error));
}
