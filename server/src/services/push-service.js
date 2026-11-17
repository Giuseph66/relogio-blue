const crypto = require('crypto');
const webpush = require('web-push');
const { VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT } = require('../config/env');
const repository = require('../repositories/push-repository');
const { HttpError } = require('../utils/http-error');

const enabled = !!(VAPID_PUBLIC_KEY && VAPID_PRIVATE_KEY && VAPID_SUBJECT);
// Validate once at startup; never expose the private key in an API response.
if (enabled) webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);
if (!enabled && (VAPID_PUBLIC_KEY || VAPID_PRIVATE_KEY || VAPID_SUBJECT)) {
  throw new Error('Configure VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY e VAPID_SUBJECT juntos.');
}
function configuration() {
  return { enabled, publicKey: enabled ? VAPID_PUBLIC_KEY : null };
}
function requireEnabled() {
  if (!enabled) throw new HttpError(503, 'Web Push não configurado no servidor.');
}
function ownerId(token) {
  if (typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token)) {
    throw new HttpError(400, 'Identificação da instalação inválida.');
  }
  return crypto.createHash('sha256').update(token).digest('hex');
}
function validateSubscription(value) {
  let url;
  try { url = new URL(value?.endpoint); } catch (_) { throw new HttpError(400, 'Endpoint de push inválido.'); }
  // A participant must not turn the application into an HTTP proxy to arbitrary hosts.
  const hosts = ['fcm.googleapis.com', 'android.googleapis.com', 'updates.push.services.mozilla.com', 'web.push.apple.com'];
  const provider = hosts.includes(url.hostname) || url.hostname.endsWith('.notify.windows.com');
  if (url.protocol !== 'https:' || url.username || url.password || url.port || !provider || url.href.length > 2048) {
    throw new HttpError(400, 'Provedor Web Push não permitido.');
  }
  const { p256dh, auth } = value?.keys || {};
  if (typeof p256dh !== 'string' || !/^[A-Za-z0-9_-]{87}$/.test(p256dh) ||
      typeof auth !== 'string' || !/^[A-Za-z0-9_-]{22}$/.test(auth)) {
    throw new HttpError(400, 'Chaves da inscrição inválidas.');
  }
  try { crypto.ECDH.convertKey(Buffer.from(p256dh, 'base64url'), 'prime256v1'); }
  catch (_) { throw new HttpError(400, 'Chave pública da inscrição inválida.'); }
  return { endpoint: url.href, keys: { p256dh, auth } };
}
async function subscribe(token, value) {
  requireEnabled();
  if (!await repository.saveSubscription(ownerId(token), validateSubscription(value))) {
    throw new HttpError(409, 'Inscrição já pertence a outra instalação. Desative os avisos e tente novamente.');
  }
  return { subscribed: true };
}
async function unsubscribe(token) {
  await repository.removeSubscription(ownerId(token));
}
function notice(title, body) {
  if (typeof title !== 'string' || !title.trim() || title.length > 80 ||
      typeof body !== 'string' || !body.trim() || body.length > 240) {
    throw new HttpError(400, 'Informe título (até 80 caracteres) e mensagem (até 240 caracteres).');
  }
  return { title: title.trim(), body: body.trim(), tag: `geonexo-push-${crypto.randomUUID()}` };
}
async function deliver(row, payload) {
  try {
    await webpush.sendNotification(JSON.parse(row.subscription_json), JSON.stringify(payload), {
      TTL: 3600, urgency: 'normal', timeout: 5000,
    });
    return 'accepted';
  } catch (error) {
    if (error.statusCode === 404 || error.statusCode === 410) {
      await repository.removeSubscription(row.id, row.subscription_json);
      return 'expired';
    }
    // Endpoint URLs and encryption keys are deliberately excluded from logs/results.
    console.warn(`[push] delivery failed: status=${Number(error.statusCode) || 'network'}`);
    return 'failed';
  }
}
async function testSubscription(token) {
  requireEnabled();
  const id = ownerId(token);
  const row = await repository.getSubscription(id);
  if (!row) throw new HttpError(404, 'Ative o Web Push neste celular antes de testar.');
  if (!await repository.claimTest(id)) throw new HttpError(429, 'Aguarde 30 segundos antes de testar novamente.');
  const status = await deliver(row, notice('GeoNexo', 'Web Push enviado pelo servidor. Toque para abrir o aplicativo.'));
  return { status };
}
let broadcasting = false;
async function broadcast(title, body) {
  requireEnabled();
  const payload = notice(title, body);
  if (broadcasting) throw new HttpError(429, 'Já existe um envio em andamento.');
  broadcasting = true;
  try {
    const rows = await repository.listSubscriptions();
    const result = { total: rows.length, accepted: 0, expired: 0, failed: 0 };
    for (let offset = 0; offset < rows.length; offset += 5) {
      const statuses = await Promise.all(rows.slice(offset, offset + 5).map(row => deliver(row, payload)));
      for (const status of statuses) result[status]++;
    }
    return result;
  } finally { broadcasting = false; }
}
async function status() {
  return { enabled, subscriptions: await repository.countSubscriptions() };
}
module.exports = { configuration, subscribe, unsubscribe, testSubscription, broadcast, status };
