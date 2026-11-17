const { getDb } = require('../db/connection');

async function saveSubscription(id, subscription) {
  const db = await getDb();
  const existing = await db.get('SELECT id FROM push_subscriptions WHERE endpoint = ?', subscription.endpoint);
  if (existing && existing.id !== id) return false;
  await db.run(`INSERT INTO push_subscriptions (id, endpoint, subscription_json, created_at, updated_at)
    VALUES (?, ?, ?, datetime('now'), datetime('now'))
    ON CONFLICT(id) DO UPDATE SET endpoint = excluded.endpoint,
      subscription_json = excluded.subscription_json, updated_at = excluded.updated_at`,
  id, subscription.endpoint, JSON.stringify(subscription));
  return true;
}
async function getSubscription(id) {
  return (await getDb()).get('SELECT * FROM push_subscriptions WHERE id = ?', id);
}
async function listSubscriptions() {
  return (await getDb()).all('SELECT * FROM push_subscriptions');
}
async function countSubscriptions() {
  return (await (await getDb()).get('SELECT COUNT(*) AS total FROM push_subscriptions')).total;
}
async function removeSubscription(id, json) {
  const db = await getDb();
  if (json) return db.run('DELETE FROM push_subscriptions WHERE id = ? AND subscription_json = ?', id, json);
  return db.run('DELETE FROM push_subscriptions WHERE id = ?', id);
}
async function claimTest(id) {
  const result = await (await getDb()).run(`UPDATE push_subscriptions SET last_test_at = datetime('now')
    WHERE id = ? AND (last_test_at IS NULL OR last_test_at <= datetime('now', '-30 seconds'))`, id);
  return result.changes === 1;
}
module.exports = { saveSubscription, getSubscription, listSubscriptions, countSubscriptions, removeSubscription, claimTest };
