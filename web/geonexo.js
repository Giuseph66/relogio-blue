/* Browser adapters. No credentials or API responses are cached by the worker. */
(() => {
  'use strict';
  const devices = new Map();
  const subscriptions = new Map();
  let listener;
  let database;
  let chooserGeneration = 0;
  let configuredService;
  let installPrompt;
  let updating = false;
  const emit = (value) => listener?.(JSON.stringify(value));

  function notificationStatus() {
    const ios = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
      (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    const installed = window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
    return {
      supported: window.isSecureContext && 'Notification' in window && 'serviceWorker' in navigator,
      permission: 'Notification' in window ? Notification.permission : 'unavailable',
      needsInstallation: ios && !installed,
    };
  }

  async function notificationRegistration() {
    const registration = await navigator.serviceWorker.getRegistration(new URL('./', document.baseURI));
    if (!registration?.active) throw new Error('Instalação offline ainda não está pronta. Reabra o aplicativo em alguns segundos.');
    return registration;
  }

  async function pushApi(action, method = 'GET', data) {
    const response = await fetch(`/api/push/${action}`, {
      method, credentials: 'same-origin', cache: 'no-store',
      headers: { 'Content-Type': 'application/json' },
      ...(data ? { body: JSON.stringify(data) } : {}),
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || 'Servidor de avisos indisponível.');
    return result;
  }

  function pushToken() {
    let token = localStorage.getItem('geonexo.push.token');
    if (!token) {
      token = Array.from(crypto.getRandomValues(new Uint8Array(32)), n => n.toString(16).padStart(2, '0')).join('');
      localStorage.setItem('geonexo.push.token', token);
    }
    return token;
  }

  async function syncPush(create) {
    const pushConfig = await pushApi('config');
    const status = notificationStatus();
    const supported = status.supported && !status.needsInstallation && 'PushManager' in window;
    if (!pushConfig.enabled || !supported || status.permission !== 'granted') {
      return { enabled: pushConfig.enabled, supported, subscribed: false };
    }
    const registration = await notificationRegistration();
    let subscription = await registration.pushManager.getSubscription();
    const encoded = pushConfig.publicKey.replace(/-/g, '+').replace(/_/g, '/');
    const key = Uint8Array.from(atob(encoded.padEnd(Math.ceil(encoded.length / 4) * 4, '=')), c => c.charCodeAt(0));
    const previousKey = subscription?.options?.applicationServerKey;
    if (previousKey && Array.from(new Uint8Array(previousKey)).join() !== Array.from(key).join()) {
      if (!create) return { enabled: true, supported, subscribed: false, hasSubscription: true };
      await subscription.unsubscribe();
      subscription = null;
    }
    if (!subscription && create) {
      subscription = await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key });
    }
    if (subscription) {
      try {
        await pushApi('subscription', 'POST', { token: pushToken(), subscription: subscription.toJSON() });
      } catch (error) {
        if (create) throw error;
        return { enabled: true, supported, subscribed: false, hasSubscription: true };
      }
    }
    return { enabled: true, supported, subscribed: !!subscription, hasSubscription: !!subscription };
  }

  async function disablePush() {
    const token = localStorage.getItem('geonexo.push.token');
    try {
      if (token) await pushApi('subscription', 'DELETE', { token });
    } finally {
      // Even an expired login must not leave this browser receiving notices after logout.
      const registration = await navigator.serviceWorker?.getRegistration(new URL('./', document.baseURI));
      const subscription = await registration?.pushManager?.getSubscription();
      if (subscription) await subscription.unsubscribe();
    }
    return { subscribed: false };
  }

  function openDatabase() {
    if (!database) {
      database = new Promise((resolve, reject) => {
        const request = indexedDB.open('geonexo', 1);
        request.onupgradeneeded = () => {
          for (const name of ['responses', 'cache']) {
            request.result.createObjectStore(name, { keyPath: 'id' });
          }
        };
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
        request.onblocked = () => reject(new Error('Feche outras abas do GeoNexo para atualizar o armazenamento.'));
      }).catch((error) => { database = null; throw error; });
    }
    return database;
  }

  async function storage(method, data) {
    const db = await openDatabase();
    if (!['responses', 'cache'].includes(data.store)) throw new Error('Armazenamento inválido');
    return new Promise((resolve, reject) => {
      const readOnly = ['db.get', 'db.all'].includes(method);
      const tx = db.transaction(data.store, readOnly ? 'readonly' : 'readwrite');
      const store = tx.objectStore(data.store);
      let value = null;
      let request;
      switch (method) {
        case 'db.get': request = store.get(data.id); break;
        case 'db.all': request = store.getAll(); break;
        case 'db.put': request = store.put(data.value); break;
        case 'db.clear': request = store.clear(); break;
        case 'db.patch':
          request = store.get(data.id);
          request.onsuccess = () => {
            if (request.result) store.put({ ...request.result, ...data.patch });
          };
          break;
        default: tx.abort(); reject(new Error('Operação inválida')); return;
      }
      if (method !== 'db.patch') request.onsuccess = () => { value = request.result ?? null; };
      tx.oncomplete = () => resolve(value);
      tx.onerror = () => reject(tx.error || request.error);
      tx.onabort = () => reject(tx.error || new Error('Não foi possível salvar os dados locais.'));
    });
  }

  function clearSubscriptions(id) {
    for (const [key, item] of subscriptions) {
      if (key.startsWith(`${id}/`)) {
        item.characteristic.removeEventListener('characteristicvaluechanged', item.handler);
        subscriptions.delete(key);
      }
    }
  }

  async function characteristic(data) {
    const device = devices.get(data.id);
    if (!device?.gatt?.connected) throw new Error('Relógio desconectado');
    const service = await device.gatt.getPrimaryService(data.service);
    return service.getCharacteristic(data.characteristic);
  }

  // Intentionally not async: requestDevice executes in the button's activation.
  function dispatch(method, data) {
    if (method.startsWith('db.')) return storage(method, data);
    switch (method) {
      case 'ble.configure': configuredService = data.service; return null;
      case 'ble.select': {
        if (!window.isSecureContext) throw new Error('Bluetooth exige HTTPS.');
        if (!navigator.bluetooth) throw new Error('Bluetooth indisponível neste navegador. Use Chrome no Android.');
        const generation = ++chooserGeneration;
        const options = { optionalServices: configuredService ? [configuredService] : data.services };
        if (data.name) options.filters = [{ namePrefix: data.name }];
        else options.acceptAllDevices = true;
        return navigator.bluetooth.requestDevice(options).then((device) => {
          if (generation !== chooserGeneration) return null;
          if (!devices.has(device.id)) {
            device.addEventListener('gattserverdisconnected', () => {
              clearSubscriptions(device.id);
              emit({ type: 'ble.disconnected', id: device.id });
            });
          }
          devices.set(device.id, device);
          return { id: device.id, name: device.name || 'Relógio' };
        });
      }
      case 'ble.stop': chooserGeneration++; return null;
      case 'ble.connect': return (async () => {
        let device = devices.get(data.id);
        if (!device && navigator.bluetooth?.getDevices) {
          for (const known of await navigator.bluetooth.getDevices()) {
            if (!devices.has(known.id)) {
              known.addEventListener('gattserverdisconnected', () => {
                clearSubscriptions(known.id);
                emit({ type: 'ble.disconnected', id: known.id });
              });
              devices.set(known.id, known);
            }
          }
          device = devices.get(data.id);
        }
        if (!device) throw new Error('Selecione novamente o relógio em Dispositivos.');
        await device.gatt.connect();
        return null;
      })();
      case 'ble.disconnect':
        clearSubscriptions(data.id);
        devices.get(data.id)?.gatt?.disconnect();
        return null;
      case 'ble.subscribe': return (async () => {
        const key = `${data.id}/${data.service}/${data.characteristic}`;
        if (subscriptions.has(key)) return null;
        const char = await characteristic(data);
        const handler = (event) => {
          const view = event.target.value;
          emit({ type: 'ble.data', id: data.id,
            bytes: Array.from(new Uint8Array(view.buffer, view.byteOffset, view.byteLength)) });
        };
        char.addEventListener('characteristicvaluechanged', handler);
        try {
          await char.startNotifications();
          subscriptions.set(key, { characteristic: char, handler });
        } catch (error) {
          char.removeEventListener('characteristicvaluechanged', handler);
          throw error;
        }
        return null;
      })();
      case 'ble.write': return (async () => {
        const char = await characteristic(data);
        const bytes = new Uint8Array(data.bytes);
        for (let offset = 0; offset < bytes.length; offset += 20) {
          const chunk = bytes.slice(offset, offset + 20);
          if (char.properties.write) await char.writeValueWithResponse(chunk);
          else await char.writeValueWithoutResponse(chunk);
          if (offset + 20 < bytes.length) await new Promise((r) => setTimeout(r, 60));
        }
        return null;
      })();
      case 'notify': return (async () => {
        const status = notificationStatus();
        if (!status.supported || status.needsInstallation || status.permission !== 'granted') return false;
        try {
          const registration = await notificationRegistration();
          await registration.showNotification(data.title, {
            body: data.body, tag: data.tag || 'geonexo',
            icon: new URL('icons/Icon-192.png', document.baseURI).href,
            data: { recordId: data.recordId || null },
          });
          return true;
        } catch (error) {
          emit({ type: 'notification.error', message: 'Não foi possível mostrar o aviso do sistema. A pergunta continua disponível no aplicativo.' });
          throw error;
        }
      })();
      case 'notify.cancel': return (async () => {
        if (!('serviceWorker' in navigator)) return null;
        const registration = await navigator.serviceWorker.getRegistration(new URL('./', document.baseURI));
        if (registration?.active) {
          for (const notification of await registration.getNotifications({ tag: data.tag })) notification.close();
        }
        return null;
      })();
      case 'notifications.status': return notificationStatus();
      case 'push.status': return syncPush(false);
      case 'push.enable': return syncPush(true);
      case 'push.disable': return disablePush();
      case 'push.test': return pushApi('test', 'POST', { token: pushToken() });
      case 'notifications.request': {
        const status = notificationStatus();
        if (status.needsInstallation) return 'install-required';
        if (!status.supported) return 'unavailable';
        // Keep requestPermission directly in the button's user activation.
        return Notification.requestPermission();
      }
      case 'update': return navigator.serviceWorker.getRegistration().then((reg) => {
        if (reg?.waiting) { updating = true; reg.waiting.postMessage('ACTIVATE_UPDATE'); }
        return null;
      });
      case 'install':
        if (!installPrompt) return false;
        return (async () => {
          const prompt = installPrompt;
          installPrompt = null;
          await prompt.prompt();
          return (await prompt.userChoice).outcome === 'accepted';
        })();
      case 'storage.persist': return navigator.storage?.persist?.() ?? false;
      case 'auth.guest': return (async () => {
        try { await disablePush(); } catch (_) { /* Browser unsubscribe still runs. */ }
        // Clear a prior admin session before entering participant mode.
        await fetch('/api/admin/auth/logout', { method: 'POST', credentials: 'same-origin' });
        const response = await fetch('/api/app/auth/guest', { method: 'POST', credentials: 'same-origin' });
        if (!response.ok) throw new Error('Não foi possível iniciar o acesso visitante.');
        return true;
      })();
      case 'auth.session':
      case 'auth.login':
      case 'auth.logout': return (async () => {
        const action = method.split('.')[1];
        if (action === 'logout') {
          try { await disablePush(); } catch (_) { /* Do not block logout when offline. */ }
        }
        const response = await fetch(`/api/admin/auth/${action}`, {
          method: action === 'session' ? 'GET' : 'POST', credentials: 'same-origin',
          headers: { 'Content-Type': 'application/json' },
          ...(action === 'login' ? { body: JSON.stringify(data) } : {}),
        });
        if (action === 'session') {
          if (response.ok) return 'admin';
          if (response.status !== 401) throw new Error('Servidor indisponível.');
          const guestResponse = await fetch('/api/app/auth/session', { credentials: 'same-origin' });
          if (!guestResponse.ok) throw new Error('Servidor indisponível.');
          return (await guestResponse.json()).authenticated ? 'guest' : 'none';
        }
        if (action === 'logout') {
          const guestResponse = await fetch('/api/app/auth/logout', { method: 'POST', credentials: 'same-origin' });
          if (!guestResponse.ok) throw new Error('Não foi possível encerrar a sessão.');
        }
        if (response.status === 401) return false;
        if (!response.ok) throw new Error('Servidor indisponível. Tente novamente.');
        return true;
      })();
      default: throw new Error(`Operação desconhecida: ${method}`);
    }
  }

  window.geonexo = {
    get bluetoothSupported() { return window.isSecureContext && !!navigator.bluetooth; },
    get updateAvailable() { return window.geonexoUpdateAvailable === true; },
    notifyUpdate() { window.geonexoUpdateAvailable = true; emit({ type: 'update' }); },
    get isVisible() { return document.visibilityState === 'visible'; },
    listen(callback) { listener = callback; },
    call(method, raw) {
      try {
        return Promise.resolve(dispatch(method, JSON.parse(raw)))
          .then((value) => JSON.stringify({ ok: true, value: value ?? null }),
            (error) => JSON.stringify({ ok: false, error: error.message || String(error) }));
      } catch (error) {
        return Promise.resolve(JSON.stringify({ ok: false, error: error.message || String(error) }));
      }
    },
  };
  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault(); installPrompt = event;
  });
  document.addEventListener('visibilitychange', () => emit({ type: 'visibility', visible: window.geonexo.isVisible }));
  navigator.serviceWorker?.addEventListener('controllerchange', () => {
    if (updating) location.reload();
  });
  navigator.serviceWorker?.addEventListener('message', (event) => {
    if (event.data?.type === 'question.open') emit(event.data);
  });
  window.addEventListener('online', () => emit({ type: 'online' }));
})();
