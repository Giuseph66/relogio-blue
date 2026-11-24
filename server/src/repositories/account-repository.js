const { getDb } = require('../db/connection');
const { nowIso } = require('../utils/helpers');

async function createUser({ id, email, passwordHash }) {
  const result = await (await getDb()).run(
    `INSERT INTO app_users (id, email, password_hash, created_at) VALUES (?, ?, ?, ?)
     ON CONFLICT(email) DO NOTHING`,
    [id, email, passwordHash, nowIso()],
  );
  return result.changes === 1;
}

async function findUserByEmail(email) {
  return (await getDb()).get('SELECT * FROM app_users WHERE email = ?', [email]);
}

async function findUserById(id) {
  return (await getDb()).get('SELECT * FROM app_users WHERE id = ?', [id]);
}

// Sessions, profile and user go together (ON DELETE CASCADE).
async function deleteUser(id) {
  await (await getDb()).run('DELETE FROM app_users WHERE id = ?', [id]);
}

async function createSession({ tokenHash, userId, expiresAt }) {
  const db = await getDb();
  await db.run('DELETE FROM app_user_sessions WHERE expires_at <= ?', [Date.now()]);
  await db.run(
    'INSERT INTO app_user_sessions (token_hash, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)',
    [tokenHash, userId, expiresAt, nowIso()],
  );
}

async function findSessionUser(tokenHash, now) {
  return (await getDb()).get(
    `SELECT app_users.id, app_users.email FROM app_user_sessions
     JOIN app_users ON app_users.id = app_user_sessions.user_id
     WHERE token_hash = ? AND expires_at > ?`,
    [tokenHash, now],
  );
}

async function deleteSession(tokenHash) {
  await (await getDb()).run('DELETE FROM app_user_sessions WHERE token_hash = ?', [tokenHash]);
}

async function getProfile(userId) {
  const row = await (await getDb()).get(
    'SELECT data_json, revision FROM user_profiles WHERE user_id = ?', [userId],
  );
  return row
    ? { profile: JSON.parse(row.data_json), revision: row.revision }
    : { profile: {}, revision: 0 };
}

// Optimistic lock: false when another device saved since `revision`.
async function saveProfile(userId, profile, revision) {
  const db = await getDb();
  const result = revision === 0
    ? await db.run(
      `INSERT INTO user_profiles (user_id, data_json, revision, updated_at) VALUES (?, ?, 1, ?)
       ON CONFLICT(user_id) DO NOTHING`,
      [userId, JSON.stringify(profile), nowIso()],
    )
    : await db.run(
      `UPDATE user_profiles SET data_json = ?, revision = revision + 1, updated_at = ?
       WHERE user_id = ? AND revision = ?`,
      [JSON.stringify(profile), nowIso(), userId, revision],
    );
  return result.changes === 1;
}

module.exports = {
  createUser, findUserByEmail, findUserById, deleteUser,
  createSession, findSessionUser, deleteSession, getProfile, saveProfile,
};
