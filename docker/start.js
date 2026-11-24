// Loads (and on the first start creates) /data/config.env, then runs the server.
// Values set in the project's .env win over generated ones.
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { createRequire } = require('module');

const CONFIG = '/data/config.env';
const serverRequire = createRequire('/srv/server/server.js');

const saved = {};
if (fs.existsSync(CONFIG)) {
  for (const line of fs.readFileSync(CONFIG, 'utf8').split('\n')) {
    const separator = line.indexOf('=');
    if (separator > 0) saved[line.slice(0, separator)] = line.slice(separator + 1);
  }
}

// Compose passes unset variables as empty strings.
for (const key of Object.keys(process.env)) if (process.env[key] === '') delete process.env[key];

const secret = () => crypto.randomBytes(32).toString('hex');
const defaults = {
  ADMIN_PASSWORD: () => crypto.randomBytes(9).toString('base64url'),
  ADMIN_COOKIE_SECRET: secret,
  APP_AUTH_TOKEN: secret,
  INTERNAL_AUTH_TOKEN: secret,
};
const script = process.argv[2]; // the jobs container only reads the configuration
let changed = false;
for (const [key, create] of Object.entries(defaults)) {
  if (process.env[key]) continue;
  if (!saved[key] && script) continue;
  if (!saved[key]) {
    saved[key] = create();
    changed = true;
  }
  process.env[key] = saved[key];
}

process.env.ADMIN_EMAIL ||= 'admin@gmail.com';
// Push subscriptions depend on this pair: created once and kept.
if (!script && !process.env.VAPID_PUBLIC_KEY && !process.env.VAPID_PRIVATE_KEY) {
  if (!saved.VAPID_PRIVATE_KEY) {
    const keys = serverRequire('web-push').generateVAPIDKeys();
    saved.VAPID_PUBLIC_KEY = keys.publicKey;
    saved.VAPID_PRIVATE_KEY = keys.privateKey;
    changed = true;
  }
  process.env.VAPID_PUBLIC_KEY = saved.VAPID_PUBLIC_KEY;
  process.env.VAPID_PRIVATE_KEY = saved.VAPID_PRIVATE_KEY;
}
if (!script) process.env.VAPID_SUBJECT ||= `mailto:${process.env.ADMIN_EMAIL}`;

if (changed) {
  const temporary = path.join('/data', '.config.env.tmp');
  fs.writeFileSync(temporary, `${Object.entries(saved).map(([k, v]) => `${k}=${v}`).join('\n')}\n`, { mode: 0o600 });
  fs.renameSync(temporary, CONFIG);
  console.log(`[docker] Segredos gerados em /data/config.env${process.env.ADMIN_PASSWORD === saved.ADMIN_PASSWORD ? '. Senha do admin: docker compose exec app grep ADMIN_PASSWORD /data/config.env' : ''}`);
}
if (!script) console.log(`[docker] Admin: ${process.env.ADMIN_EMAIL}`);

require(script || '/srv/server/server.js');
