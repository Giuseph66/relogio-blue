const {
  listActiveLocations,
  listRulesByLocationIds,
} = require('../repositories/catalog-repository');
const { listActiveQuestions } = require('../repositories/question-repository');
const { upsertDevice } = require('../repositories/device-repository');
const {
  haversineDistanceMeters,
  normalizeCity,
  toNullableNumber,
} = require('../utils/helpers');
const { HttpError } = require('../utils/http-error');

async function resolveLocation(payload) {
  const deviceId = String(payload.deviceId || '').trim();
  const deviceName = String(payload.deviceName || '').trim() || null;
  const city = normalizeCity(payload.city);
  const latitude = toNullableNumber(payload.latitude);
  const longitude = toNullableNumber(payload.longitude);

  if (!deviceId) {
    throw new HttpError(400, 'deviceId is required');
  }

  if (!city && (latitude === null || longitude === null)) {
    throw new HttpError(400, 'city or latitude/longitude is required');
  }

  const device = await upsertDevice({
    id: deviceId,
    name: deviceName,
    city,
    latitude,
    longitude,
    status: 'active',
  });

  const locations = await listActiveLocations();
  console.log(`[resolveLocation] total de locais ativos no DB: ${locations.length}`);
  const matches = locations
    .map((location) => {
      const distanceMeters = haversineDistanceMeters(
        latitude,
        longitude,
        location.latitude,
        location.longitude,
      );

      const cityMatched =
        city && location.city && normalizeCity(location.city) === city;
      const coordinateMatched =
        distanceMeters !== null && distanceMeters <= Number(location.radius_meters);

      console.log(`[resolveLocation] local "${location.name}": cidade_db="${location.city}" cidade_req="${city}" cityMatch=${cityMatched} | distancia=${distanceMeters?.toFixed(0)}m raio=${location.radius_meters}m coordMatch=${coordinateMatched}`);

      if (!cityMatched && !coordinateMatched) {
        return null;
      }

      const matchedBy = [];
      if (cityMatched) matchedBy.push('city');
      if (coordinateMatched) matchedBy.push('coordinates');

      return {
        id: location.id,
        name: location.name,
        city: location.city,
        latitude: location.latitude,
        longitude: location.longitude,
        radiusMeters: location.radius_meters,
        isActive: Boolean(location.is_active),
        createdAt: location.created_at,
        distanceMeters: distanceMeters === null ? null : Number(distanceMeters.toFixed(2)),
        matchedBy,
      };
    })
    .filter(Boolean)
    .sort((left, right) => {
      if (left.distanceMeters === null) return 1;
      if (right.distanceMeters === null) return -1;
      return left.distanceMeters - right.distanceMeters;
    });

  const rules = await listRulesByLocationIds(matches.map((match) => match.id));
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

  const matchedLocationIds = matches.map((match) => match.id);
  const questions = await listActiveQuestions({
    city,
    locationIds: matchedLocationIds,
  });

  return {
    device: serializeDevice(device),
    context: {
      city,
      latitude,
      longitude,
    },
    locations: matches.map((match) => ({
      ...match,
      rules: rulesByLocation.get(match.id) || [],
    })),
    questions,
  };
}

function serializeDevice(device) {
  if (!device) return null;

  return {
    id: device.id,
    name: device.name,
    lastCity: device.last_city,
    lastLatitude: device.last_latitude,
    lastLongitude: device.last_longitude,
    lastSeenAt: device.last_seen_at,
    lastSyncAt: device.last_sync_at,
    status: device.status,
    createdAt: device.created_at,
    updatedAt: device.updated_at,
  };
}

module.exports = {
  resolveLocation,
  serializeDevice,
};
