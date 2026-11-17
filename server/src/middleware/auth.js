const {
  ENABLE_APP_AUTH,
  APP_AUTH_TOKEN,
  INTERNAL_AUTH_TOKEN,
  ALLOW_LEGACY_MESSAGE_POST_WITHOUT_AUTH,
  ADMIN_EMAIL,
  ADMIN_PASSWORD,
  ADMIN_COOKIE_NAME,
  ADMIN_COOKIE_SECRET,
  ADMIN_SESSION_HOURS,
} = require('../config/env');
const crypto = require('crypto');

function extractToken(req) {
  const authHeader = req.headers.authorization || '';
  if (authHeader.startsWith('Bearer ')) {
    return authHeader.slice(7).trim();
  }

  const apiKey = req.headers['x-api-key'];
  return apiKey ? String(apiKey).trim() : null;
}

function requireAppAuth(options = {}) {
  const allowWithoutAuth = Boolean(options.allowWithoutAuth);

  return function appAuthMiddleware(req, res, next) {
    if (!ENABLE_APP_AUTH || allowWithoutAuth) {
      next();
      return;
    }

    const token = extractToken(req);
    if ((token && token === APP_AUTH_TOKEN) || getAdminSession(req) || getAppSession(req)) {
      next();
      return;
    }

    res.status(401).json({ error: 'unauthorized' });
  };
}

function requireLegacyMessagePostAuth() {
  return requireAppAuth({
    allowWithoutAuth: ALLOW_LEGACY_MESSAGE_POST_WITHOUT_AUTH,
  });
}

function requireInternalAuth(req, res, next) {
  const token = extractToken(req);
  const isAppEngineCron = process.env.GAE_ENV === 'standard' && req.headers['x-appengine-cron'] === 'true';

  if (isAppEngineCron || (token && token === INTERNAL_AUTH_TOKEN)) {
    next();
    return;
  }

  res.status(401).json({ error: 'unauthorized' });
}

function parseCookies(req) {
  const raw = req.headers.cookie || '';
  return raw.split(';').reduce((acc, pair) => {
    const separatorIndex = pair.indexOf('=');
    if (separatorIndex <= 0) return acc;
    const key = pair.slice(0, separatorIndex).trim();
    const value = pair.slice(separatorIndex + 1).trim();
    acc[key] = decodeURIComponent(value);
    return acc;
  }, {});
}

function signValue(value) {
  return crypto
    .createHmac('sha256', ADMIN_COOKIE_SECRET)
    .update(value)
    .digest('hex');
}

function serializeSession(payload) {
  const encoded = Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
  const signature = signValue(encoded);
  return `${encoded}.${signature}`;
}

function deserializeSession(token) {
  if (!token || !token.includes('.')) return null;
  const [encoded, signature] = token.split('.');
  if (!encoded || !signature) return null;
  if (signValue(encoded) !== signature) return null;

  try {
    const payload = JSON.parse(
      Buffer.from(encoded, 'base64url').toString('utf8'),
    );
    if (!payload?.email || !payload?.exp) return null;
    if (Date.now() > payload.exp) return null;
    return payload;
  } catch (_) {
    return null;
  }
}

function getAdminSession(req) {
  const cookies = parseCookies(req);
  const sessionToken = cookies[ADMIN_COOKIE_NAME];
  const session = deserializeSession(sessionToken);
  return session && !session.type ? session : null;
}

// Separate cookie and type: a participant session never grants admin access.
const APP_COOKIE_NAME = 'geonexo_app_session';
function getAppSession(req) {
  const session = deserializeSession(parseCookies(req)[APP_COOKIE_NAME]);
  return session?.type === 'app' ? session : null;
}
function setAppSessionCookie(res) {
  const token = serializeSession({ email: 'guest', type: 'app', exp: Date.now() + ADMIN_SESSION_HOURS * 3600000 });
  res.cookie(APP_COOKIE_NAME, token, { httpOnly: true, sameSite: 'lax', path: '/', maxAge: ADMIN_SESSION_HOURS * 3600000 });
}
function clearAppSessionCookie(res) {
  res.clearCookie(APP_COOKIE_NAME, { httpOnly: true, sameSite: 'lax', path: '/' });
}

function createAdminSession(email = ADMIN_EMAIL) {
  return serializeSession({
    email,
    exp: Date.now() + ADMIN_SESSION_HOURS * 60 * 60 * 1000,
  });
}

function clearAdminSessionCookie(res) {
  res.setHeader(
    'Set-Cookie',
    `${ADMIN_COOKIE_NAME}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0`,
  );
}

function setAdminSessionCookie(res, token) {
  res.setHeader(
    'Set-Cookie',
    `${ADMIN_COOKIE_NAME}=${encodeURIComponent(
      token,
    )}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${ADMIN_SESSION_HOURS * 60 * 60}`,
  );
}

function isInternalRequest(req) {
  const token = extractToken(req);
  return (
    (process.env.GAE_ENV === 'standard' && req.headers['x-appengine-cron'] === 'true') ||
    (token && token === INTERNAL_AUTH_TOKEN)
  );
}

function requireAdminApiAuth(req, res, next) {
  if (isInternalRequest(req) || getAdminSession(req)) {
    next();
    return;
  }

  res.status(401).json({ error: 'unauthorized' });
}

function requireAdminPageAuth(req, res, next) {
  if (getAdminSession(req)) {
    next();
    return;
  }

  res.redirect('/admin/login');
}

function requireGuestAdminPage(req, res, next) {
  if (getAdminSession(req)) {
    res.redirect('/admin');
    return;
  }

  next();
}

function validateAdminCredentials(email, password) {
  return email === ADMIN_EMAIL && password === ADMIN_PASSWORD;
}

module.exports = {
  getAppSession, setAppSessionCookie, clearAppSessionCookie,
  requireAppAuth,
  requireLegacyMessagePostAuth,
  requireInternalAuth,
  requireAdminApiAuth,
  requireAdminPageAuth,
  requireGuestAdminPage,
  createAdminSession,
  setAdminSessionCookie,
  clearAdminSessionCookie,
  getAdminSession,
  validateAdminCredentials,
};
