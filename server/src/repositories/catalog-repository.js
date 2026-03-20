const { getDb } = require('../db/connection');
const { createId, nowIso, normalizeCity } = require('../utils/helpers');

async function listLocations() {
  const db = await getDb();
  const locations = await db.all(
    `
      SELECT *
      FROM locations
      ORDER BY name ASC
    `,
  );

  const rules = await db.all(
    `
      SELECT *
      FROM location_rules
      ORDER BY priority ASC, created_at ASC
    `,
  );

  const rulesByLocation = new Map();
  for (const rule of rules) {
    const items = rulesByLocation.get(rule.location_id) || [];
    items.push({
      id: rule.id,
      ruleType: rule.rule_type,
      ruleValue: rule.rule_value,
      priority: rule.priority,
      isActive: Boolean(rule.is_active),
    });
    rulesByLocation.set(rule.location_id, items);
  }

  return locations.map((location) => ({
    id: location.id,
    name: location.name,
    city: location.city,
    latitude: location.latitude,
    longitude: location.longitude,
    radiusMeters: location.radius_meters,
    isActive: Boolean(location.is_active),
    createdAt: location.created_at,
    updatedAt: location.updated_at,
    rules: rulesByLocation.get(location.id) || [],
  }));
}

async function listActiveLocations() {
  const db = await getDb();
  return db.all(
    `
      SELECT *
      FROM locations
      WHERE is_active = 1
      ORDER BY name ASC
    `,
  );
}

async function listRulesByLocationIds(locationIds) {
  if (!locationIds.length) return [];

  const db = await getDb();
  const placeholders = locationIds.map(() => '?').join(', ');
  return db.all(
    `
      SELECT *
      FROM location_rules
      WHERE location_id IN (${placeholders}) AND is_active = 1
      ORDER BY priority ASC, created_at ASC
    `,
    locationIds,
  );
}

async function createLocation(payload) {
  const db = await getDb();
  const timestamp = nowIso();
  const id = createId('loc');

  await db.run(
    `
      INSERT INTO locations (
        id, name, city, latitude, longitude, radius_meters, is_active, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `,
    [
      id,
      payload.name,
      normalizeCity(payload.city),
      payload.latitude,
      payload.longitude,
      payload.radiusMeters ?? 100,
      payload.isActive === false ? 0 : 1,
      timestamp,
      timestamp,
    ],
  );

  if (Array.isArray(payload.rules)) {
    await replaceLocationRules(id, payload.rules);
  }

  return getLocationById(id);
}

async function getLocationById(id) {
  const locations = await listLocations();
  return locations.find((location) => location.id === id) || null;
}

async function updateLocation(id, payload) {
  const db = await getDb();
  const current = await db.get(`SELECT * FROM locations WHERE id = ?`, [id]);
  if (!current) return null;

  const timestamp = nowIso();
  await db.run(
    `
      UPDATE locations
      SET name = ?, city = ?, latitude = ?, longitude = ?, radius_meters = ?, is_active = ?, updated_at = ?
      WHERE id = ?
    `,
    [
      payload.name ?? current.name,
      normalizeCity(payload.city ?? current.city),
      payload.latitude ?? current.latitude,
      payload.longitude ?? current.longitude,
      payload.radiusMeters ?? current.radius_meters,
      payload.isActive === undefined ? current.is_active : payload.isActive ? 1 : 0,
      timestamp,
      id,
    ],
  );

  if (Array.isArray(payload.rules)) {
    await replaceLocationRules(id, payload.rules);
  }

  return getLocationById(id);
}

async function deleteLocation(id) {
  const db = await getDb();
  const result = await db.run(`DELETE FROM locations WHERE id = ?`, [id]);
  return result.changes > 0;
}

async function replaceLocationRules(locationId, rules) {
  const db = await getDb();
  const timestamp = nowIso();

  await db.run(`DELETE FROM location_rules WHERE location_id = ?`, [locationId]);

  for (let index = 0; index < rules.length; index += 1) {
    const rule = rules[index];
    await db.run(
      `
        INSERT INTO location_rules (
          id, location_id, rule_type, rule_value, priority, is_active, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        createId('rule'),
        locationId,
        rule.ruleType,
        rule.ruleValue,
        rule.priority ?? index,
        rule.isActive === false ? 0 : 1,
        timestamp,
        timestamp,
      ],
    );
  }
}

async function countLocations() {
  const db = await getDb();
  const row = await db.get(`SELECT COUNT(*) AS total FROM locations`);
  return row.total;
}

module.exports = {
  listLocations,
  listActiveLocations,
  listRulesByLocationIds,
  createLocation,
  getLocationById,
  updateLocation,
  deleteLocation,
  countLocations,
};
