const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

function asBoolean(value, fallback) {
  if (value === undefined) return fallback;
  return String(value).toLowerCase() === 'true';
}

const ROOT_DIR = path.resolve(__dirname, '..', '..');
const DATA_DIR = path.join(ROOT_DIR, 'data');
const VIEWS_DIR = path.join(ROOT_DIR, 'src', 'views');

loadEnvFiles([
  path.join(ROOT_DIR, '.env'),
  path.join(ROOT_DIR, '.env.local'),
]);

// No well-known default: without ADMIN_PASSWORD nobody can sign in as admin.
function unsetAdminPassword() {
  console.warn('[server] ADMIN_PASSWORD não definida: login de administrador desativado.');
  return crypto.randomBytes(32).toString('hex');
}

function loadEnvFiles(filePaths) {
  for (const filePath of filePaths) {
    if (!fs.existsSync(filePath)) continue;

    const contents = fs.readFileSync(filePath, 'utf8');
    for (const rawLine of contents.split(/\r?\n/)) {
      const line = rawLine.trim();
      if (!line || line.startsWith('#')) continue;

      const separatorIndex = line.indexOf('=');
      if (separatorIndex <= 0) continue;

      const key = line.slice(0, separatorIndex).trim();
      let value = line.slice(separatorIndex + 1).trim();

      if (
        (value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))
      ) {
        value = value.slice(1, -1);
      }

      if (process.env[key] === undefined) {
        process.env[key] = value;
      }
    }
  }
}

module.exports = {
  NODE_ENV: process.env.NODE_ENV || 'development',
  PORT: Number(process.env.PORT || 3001),
  // Who may set X-Forwarded-*: the reverse proxy in front of Node.
  TRUST_PROXY: process.env.TRUST_PROXY || 'loopback',
  HOST: process.env.HOST || '0.0.0.0',
  VAPID_PUBLIC_KEY: process.env.VAPID_PUBLIC_KEY || '',
  VAPID_PRIVATE_KEY: process.env.VAPID_PRIVATE_KEY || '',
  VAPID_SUBJECT: process.env.VAPID_SUBJECT || '',
  DB_PATH: process.env.DB_PATH || path.join(DATA_DIR, 'app.db'),
  PUBLIC_DIR: path.join(ROOT_DIR, 'public'),
  PWA_DIR: path.resolve(process.env.PWA_DIR || path.join(ROOT_DIR, 'public', 'app')),
  VIEWS_DIR,
  APP_AUTH_TOKEN: process.env.APP_AUTH_TOKEN || 'dev-mobile-token',
  INTERNAL_AUTH_TOKEN: process.env.INTERNAL_AUTH_TOKEN || 'dev-internal-token',
  ENABLE_APP_AUTH: asBoolean(process.env.ENABLE_APP_AUTH, true),
  ADMIN_EMAIL: process.env.ADMIN_EMAIL || 'admin@gmail.com',
  ADMIN_PASSWORD: process.env.ADMIN_PASSWORD || unsetAdminPassword(),
  ADMIN_COOKIE_NAME: process.env.ADMIN_COOKIE_NAME || 'rb_admin_session',
  ADMIN_COOKIE_SECRET:
    process.env.ADMIN_COOKIE_SECRET || 'relogio-blutu-admin-secret',
  ADMIN_SESSION_HOURS: Number(process.env.ADMIN_SESSION_HOURS || 12),
  ALLOW_LEGACY_MESSAGE_POST_WITHOUT_AUTH: asBoolean(
    process.env.ALLOW_LEGACY_MESSAGE_POST_WITHOUT_AUTH,
    true,
  ),
  MESSAGE_RETENTION_LIMIT: Number(process.env.MESSAGE_RETENTION_LIMIT || 500),
  STALE_JOB_MINUTES: Number(process.env.STALE_JOB_MINUTES || 15),
  JOB_BATCH_SIZE: Number(process.env.JOB_BATCH_SIZE || 100),
  JOB_HISTORY_RETENTION_DAYS: Number(
    process.env.JOB_HISTORY_RETENTION_DAYS || 30,
  ),
  SEED_SAMPLE_DATA: asBoolean(process.env.SEED_SAMPLE_DATA, false),
  NOMINATIM_BASE_URL:
    process.env.NOMINATIM_BASE_URL || 'https://nominatim.openstreetmap.org',
  OVERPASS_BASE_URL:
    process.env.OVERPASS_BASE_URL || 'https://overpass-api.de/api/interpreter',
};
