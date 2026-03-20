const { resolveLocation } = require('../services/location-service');
const { listActiveLocations } = require('../repositories/catalog-repository');

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

module.exports = {
  resolve,
  listPublic,
};
