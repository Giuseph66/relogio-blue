const {
  createAdminSession,
  setAdminSessionCookie,
  clearAdminSessionCookie,
  getAdminSession,
  validateAdminCredentials,
} = require('../middleware/auth');
const { ADMIN_EMAIL } = require('../config/env');
const { claimAttempt, clearAttempts } = require('../utils/login-attempts');
const { HttpError } = require('../utils/http-error');

async function login(req, res) {
  const email = String(req.body?.email || '').trim();
  const password = String(req.body?.password || '').trim();

  const attempt = `${req.ip}|admin`;
  const target = email.toLowerCase() === ADMIN_EMAIL.trim().toLowerCase();
  if (target) claimAttempt(attempt);
  if (!validateAdminCredentials(email, password)) {
    throw new HttpError(401, 'invalid credentials');
  }
  clearAttempts(attempt);

  const sessionToken = createAdminSession(email);
  if (req.body?.client === 'native') {
    res.status(200).json({ ok: true, admin: { email }, token: sessionToken });
    return;
  }
  setAdminSessionCookie(res, sessionToken);

  res.status(200).json({
    ok: true,
    admin: { email },
  });
}

async function logout(req, res) {
  clearAdminSessionCookie(res);
  res.status(200).json({ ok: true });
}

async function session(req, res) {
  const currentSession = getAdminSession(req);
  if (!currentSession) {
    res.status(401).json({ authenticated: false });
    return;
  }

  res.status(200).json({
    authenticated: true,
    admin: {
      email: currentSession.email,
    },
  });
}

module.exports = {
  login,
  logout,
  session,
};
