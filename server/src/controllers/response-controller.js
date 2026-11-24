const crypto = require('crypto');
const { ingestResponse } = require('../services/response-service');
const { extractToken, getAdminSession, parseCookies } = require('../middleware/auth');
const { HttpError } = require('../utils/http-error');

const DEVICE_COOKIE = 'geonexo_device';
const DEVICE_COOKIE_MS = 400 * 24 * 3600000; // longest lifetime browsers accept

// The app sends a hash of the phone's ANDROID_ID, which survives reinstalling.
// Browsers expose no hardware identifier: they get an HttpOnly cookie.
function identifyDevice(req, res) {
  if (extractToken(req)) {
    const id = String(req.body?.deviceId || '');
    if (/^(android-[0-9a-f]{64}|app-[0-9a-f-]{36})$/.test(id)) {
      return { deviceKey: id, deviceId: 'mobile-app' };
    }
    // Older versions sent the same id from every phone.
    throw new HttpError(426, 'Atualize o aplicativo para enviar respostas.');
  }
  // A tab makes it trivial to look like a new device (private window). The
  // header is a deterrent: the server cannot prove how a page was opened.
  if (req.headers['x-geonexo-app'] !== 'pwa') {
    throw new HttpError(403, 'Para responder, use o aplicativo instalado.');
  }
  const current = parseCookies(req)[DEVICE_COOKIE];
  const id = /^[0-9a-f]{32}$/.test(current || '') ? current : crypto.randomBytes(16).toString('hex');
  res.cookie(DEVICE_COOKIE, id, {
    httpOnly: true, sameSite: 'lax', path: '/', secure: req.secure, maxAge: DEVICE_COOKIE_MS,
  });
  return { deviceKey: `web-${id}`, deviceId: 'web-app' };
}

async function createResponse(req, res) {
  const admin = !!getAdminSession(req);
  if (!admin && req.headers['x-admin-session']) {
    // Do not judge an administrator's answer as a participant's one.
    throw new HttpError(401, 'Sessão de administrador expirada. Entre novamente.');
  }
  const device = admin ? { deviceId: extractToken(req) ? 'mobile-app' : 'web-app' } : identifyDevice(req, res);
  const result = await ingestResponse(req.body || {}, { admin, ...device });
  res.status(result.created ? 201 : 200).json({
    ok: true,
    created: result.created,
    response: result.response,
  });
}

module.exports = {
  createResponse,
};
