const {
  createAdminSession,
  setAdminSessionCookie,
  clearAdminSessionCookie,
  getAdminSession,
  validateAdminCredentials,
} = require('../middleware/auth');
const { HttpError } = require('../utils/http-error');

async function login(req, res) {
  const email = String(req.body?.email || '').trim();
  const password = String(req.body?.password || '').trim();

  if (!validateAdminCredentials(email, password)) {
    throw new HttpError(401, 'invalid credentials');
  }

  const sessionToken = createAdminSession(email);
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
