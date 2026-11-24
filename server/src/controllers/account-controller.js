const service = require('../services/account-service');
const repository = require('../repositories/account-repository');
const { validateProfile } = require('../services/profile-validator');
const { getAccountSession, setAccountCookie, clearAccountCookie } = require('../middleware/auth');
const { HttpError } = require('../utils/http-error');

// Browsers only get the HttpOnly cookie; the native app, without cookies, gets the token.
function sendSession(req, res, status, { token, user }) {
  if (req.body?.client === 'native') {
    res.status(status).json({ user, token });
    return;
  }
  setAccountCookie(req, res, token);
  res.status(status).json({ user });
}

async function register(req, res) {
  sendSession(req, res, 201, await service.register(req.body));
}

async function login(req, res) {
  sendSession(req, res, 200, await service.login(req.body, req.ip));
}

async function session(req, res) {
  const current = await getAccountSession(req);
  res.json({ user: current ? current.user : null });
}

async function logout(req, res) {
  const current = await getAccountSession(req);
  if (current) await repository.deleteSession(current.tokenHash);
  clearAccountCookie(req, res);
  res.json({ ok: true });
}

async function remove(req, res) {
  await service.removeAccount(req.account.user.id, req.body?.password, req.ip);
  clearAccountCookie(req, res);
  res.json({ ok: true });
}

async function getProfile(req, res) {
  res.json(await repository.getProfile(req.account.user.id));
}

async function putProfile(req, res) {
  const userId = req.account.user.id;
  const profile = validateProfile(req.body?.profile);
  const revision = req.body?.revision;
  if (!Number.isInteger(revision) || revision < 0) throw new HttpError(400, 'Revisão inválida.');
  if (await repository.saveProfile(userId, profile, revision)) {
    res.json({ profile, revision: revision + 1 });
    return;
  }
  // Saved by another device: the client merges with this copy and retries.
  res.status(409).json(await repository.getProfile(userId));
}

module.exports = { register, login, session, logout, remove, getProfile, putProfile };
