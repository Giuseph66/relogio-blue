const { HttpError } = require('./http-error');

const WINDOW_MS = 15 * 60000;
const MAX_FAILURES = 10;
const failures = new Map(); // key -> { count, resetAt }

// Counts the attempt before the (slow) hash, so parallel guesses cannot slip through.
function claimAttempt(key) {
  const now = Date.now();
  if (failures.size > 5000) {
    for (const [item, entry] of failures) if (entry.resetAt <= now) failures.delete(item);
  }
  let entry = failures.get(key);
  if (!entry || entry.resetAt <= now) {
    entry = { count: 0, resetAt: now + WINDOW_MS };
    failures.set(key, entry);
  }
  if (entry.count >= MAX_FAILURES) {
    throw new HttpError(429, 'Muitas tentativas. Aguarde 15 minutos e tente de novo.');
  }
  entry.count += 1;
}

function clearAttempts(key) {
  failures.delete(key);
}

module.exports = { claimAttempt, clearAttempts };
