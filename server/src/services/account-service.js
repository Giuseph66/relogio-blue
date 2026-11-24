const crypto = require('crypto');
const { promisify } = require('util');
const { ADMIN_EMAIL } = require('../config/env');
const { createId } = require('../utils/helpers');
const { HttpError } = require('../utils/http-error');
const { ACCOUNT_SESSION_MS, hashToken } = require('../middleware/auth');
const { claimAttempt, clearAttempts } = require('../utils/login-attempts');
const repository = require('../repositories/account-repository');

const scrypt = promisify(crypto.scrypt);

async function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const key = await scrypt(password, salt, 32);
  return `${salt.toString('hex')}:${key.toString('hex')}`;
}

async function verifyPassword(password, stored) {
  const [salt, key] = stored.split(':').map((part) => Buffer.from(part, 'hex'));
  return crypto.timingSafeEqual(await scrypt(password, salt, 32), key);
}

// Same cost for unknown e-mails, so timing does not reveal who has an account.
const dummyHash = hashPassword(crypto.randomBytes(16).toString('hex'));

function parseCredentials(body) {
  const email = String(body?.email ?? '').trim().toLowerCase();
  const password = typeof body?.password === 'string' ? body.password : '';
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpError(400, 'Informe um e-mail válido.');
  }
  if (password.length > 200) throw new HttpError(400, 'Senha muito longa.');
  return { email, password };
}

async function openSession(user) {
  const token = crypto.randomBytes(32).toString('base64url');
  await repository.createSession({
    tokenHash: hashToken(token), userId: user.id, expiresAt: Date.now() + ACCOUNT_SESSION_MS,
  });
  return { token, user: { id: user.id, email: user.email } };
}

async function register(body) {
  const { email, password } = parseCredentials(body);
  if (password.length < 8) throw new HttpError(400, 'A senha precisa ter pelo menos 8 caracteres.');
  const taken = new HttpError(409, 'Já existe uma conta com este e-mail. Use "Entrar".');
  if (email === ADMIN_EMAIL.trim().toLowerCase() || await repository.findUserByEmail(email)) throw taken;
  const user = { id: createId('usr'), email, passwordHash: await hashPassword(password) };
  if (!await repository.createUser(user)) throw taken;
  return openSession(user);
}

async function login(body, ip) {
  const { email, password } = parseCredentials(body);
  const key = `${ip}|${email}`;
  claimAttempt(key);
  const user = await repository.findUserByEmail(email);
  const valid = await verifyPassword(password, user ? user.password_hash : await dummyHash);
  if (!user || !valid) throw new HttpError(401, 'E-mail ou senha incorretos.');
  clearAttempts(key);
  return openSession(user);
}

async function removeAccount(userId, password, ip) {
  const key = `${ip}|${userId}`;
  claimAttempt(key);
  const user = await repository.findUserById(userId);
  if (typeof password !== 'string' || password.length > 200
    || !await verifyPassword(password, user.password_hash)) {
    throw new HttpError(403, 'Senha incorreta.');
  }
  clearAttempts(key);
  await repository.deleteUser(userId);
}

module.exports = { register, login, removeAccount };
