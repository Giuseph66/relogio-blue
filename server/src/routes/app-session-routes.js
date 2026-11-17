const { Router } = require('express');
const { getAppSession, setAppSessionCookie, clearAppSessionCookie } = require('../middleware/auth');
const router = Router();
router.post('/guest', (req, res) => {
  setAppSessionCookie(res);
  res.json({ ok: true });
});
router.get('/session', (req, res) => {
  res.json({ authenticated: !!getAppSession(req) });
});
router.post('/logout', (req, res) => {
  clearAppSessionCookie(res);
  res.json({ ok: true });
});
module.exports = { appSessionRoutes: router };
