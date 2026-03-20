const { getDb } = require('../db/connection');
const { nowIso } = require('../utils/helpers');

async function upsertDevice({
  id,
  name = null,
  city = null,
  latitude = null,
  longitude = null,
  status = 'active',
}) {
  const db = await getDb();
  const timestamp = nowIso();

  await db.run(
    `
      INSERT INTO devices (
        id, name, last_city, last_latitude, last_longitude, last_seen_at, status, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = COALESCE(excluded.name, devices.name),
        last_city = COALESCE(excluded.last_city, devices.last_city),
        last_latitude = COALESCE(excluded.last_latitude, devices.last_latitude),
        last_longitude = COALESCE(excluded.last_longitude, devices.last_longitude),
        last_seen_at = excluded.last_seen_at,
        status = excluded.status,
        updated_at = excluded.updated_at
    `,
    [id, name, city, latitude, longitude, timestamp, status, timestamp, timestamp],
  );

  return getDeviceById(id);
}

async function getDeviceById(id) {
  const db = await getDb();
  return db.get(`SELECT * FROM devices WHERE id = ?`, [id]);
}

async function markDeviceSynced(id) {
  const db = await getDb();
  const timestamp = nowIso();
  await db.run(
    `
      UPDATE devices
      SET last_sync_at = ?, updated_at = ?, status = 'synced'
      WHERE id = ?
    `,
    [timestamp, timestamp, id],
  );
}

async function countDevices() {
  const db = await getDb();
  const row = await db.get(`SELECT COUNT(*) AS total FROM devices`);
  return row.total;
}

async function listRecentDevices(limit = 8) {
  const db = await getDb();
  return db.all(
    `
      SELECT id, name, last_city AS lastCity, last_latitude AS lastLatitude,
             last_longitude AS lastLongitude, last_seen_at AS lastSeenAt,
             last_sync_at AS lastSyncAt, status, created_at AS createdAt, updated_at AS updatedAt
      FROM devices
      ORDER BY COALESCE(last_seen_at, created_at) DESC
      LIMIT ?
    `,
    [limit],
  );
}

module.exports = {
  upsertDevice,
  getDeviceById,
  markDeviceSynced,
  countDevices,
  listRecentDevices,
};
