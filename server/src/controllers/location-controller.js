const { resolveLocation } = require('../services/location-service');
const { listActiveLocations } = require('../repositories/catalog-repository');
const { listAllActiveQuestions } = require('../repositories/question-repository');

async function resolve(req, res) {
  const payload = req.method === 'GET' ? req.query : req.body;
  console.log('[location/resolve] payload recebido:', JSON.stringify(payload));
  const result = await resolveLocation(payload || {});
  console.log(`[location/resolve] locais encontrados: ${result.locations.length}`, result.locations.map(l => `${l.name} (${l.matchedBy})`));
  res.status(200).json(result);
}

async function listPublic(req, res) {
  const rows = await listActiveLocations();
  const locations = rows.map((loc) => ({
    id: loc.id,
    name: loc.name,
    latitude: loc.latitude,
    longitude: loc.longitude,
    radiusMeters: loc.radius_meters,
    createdAt: loc.created_at,
  }));
  res.status(200).json({ locations });
}

/**
 * Everything the app needs to detect visits and pick questions without
 * network: all active locations + all active questions (with options).
 */
async function offlineBundle(req, res) {
  const [rows, questions] = await Promise.all([
    listActiveLocations(),
    listAllActiveQuestions(),
  ]);
  const locations = rows.map((loc) => ({
    id: loc.id,
    name: loc.name,
    city: loc.city,
    latitude: loc.latitude,
    longitude: loc.longitude,
    radiusMeters: loc.radius_meters,
  }));
  res.status(200).json({
    generatedAt: new Date().toISOString(),
    locations,
    questions,
  });
}

module.exports = {
  resolve,
  listPublic,
  offlineBundle,
};
