const { getDeviceById, markDeviceSynced, upsertDevice } = require('../repositories/device-repository');
const { listRecentResponsesByDevice, countPendingResponses } = require('../repositories/response-repository');
const { countJobsByStatus } = require('../repositories/job-repository');
const { listActiveQuestions, listAnsweredQuestionIdsByDevice } = require('../repositories/question-repository');
const { listActiveLocations, listRulesByLocationIds } = require('../repositories/catalog-repository');
const {
  haversineDistanceMeters,
  normalizeCity,
  nowIso,
  toNullableNumber,
} = require('../utils/helpers');
const { HttpError } = require('../utils/http-error');
const { serializeDevice } = require('./location-service');

async function buildSyncPayload(payload) {
  const deviceId = String(payload.deviceId || '').trim();
  if (!deviceId) {
    throw new HttpError(400, 'deviceId is required');
  }

  const city = normalizeCity(payload.city);
  const latitude = toNullableNumber(payload.latitude);
  const longitude = toNullableNumber(payload.longitude);

  let device = await getDeviceById(deviceId);
  if (!device) {
    device = await upsertDevice({
      id: deviceId,
      name: payload.deviceName || null,
      city,
      latitude,
      longitude,
      status: 'active',
    });
  } else if (city || latitude !== null || longitude !== null) {
    device = await upsertDevice({
      id: deviceId,
      name: payload.deviceName || device.name,
      city: city || device.last_city,
      latitude: latitude === null ? device.last_latitude : latitude,
      longitude: longitude === null ? device.last_longitude : longitude,
      status: 'active',
    });
  }

  const effectiveCity = city || normalizeCity(device.last_city);
  const effectiveLatitude =
    latitude === null ? toNullableNumber(device.last_latitude) : latitude;
  const effectiveLongitude =
    longitude === null ? toNullableNumber(device.last_longitude) : longitude;

  const locations = await listActiveLocations();
  const matchedLocations = locations
    .map((location) => {
      const distanceMeters = haversineDistanceMeters(
        effectiveLatitude,
        effectiveLongitude,
        location.latitude,
        location.longitude,
      );
      const cityMatched =
        effectiveCity &&
        location.city &&
        normalizeCity(location.city) === effectiveCity;
      const coordinateMatched =
        distanceMeters !== null && distanceMeters <= Number(location.radius_meters);

      if (!cityMatched && !coordinateMatched) return null;

      return {
        id: location.id,
        name: location.name,
        city: location.city,
        latitude: location.latitude,
        longitude: location.longitude,
        radiusMeters: location.radius_meters,
        distanceMeters: distanceMeters === null ? null : Number(distanceMeters.toFixed(2)),
      };
    })
    .filter(Boolean);

  const matchedLocationIds = matchedLocations.map((location) => location.id);
  const [rules, questions, answeredQuestionIds, recentResponses, jobsByStatus, pendingResponses] =
    await Promise.all([
      listRulesByLocationIds(matchedLocationIds),
      listActiveQuestions({
        city: effectiveCity,
        locationIds: matchedLocationIds,
        now: nowIso(),
      }),
      listAnsweredQuestionIdsByDevice(deviceId),
      listRecentResponsesByDevice(deviceId, 20),
      countJobsByStatus(),
      countPendingResponses(),
    ]);

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

  const pendingQuestions = questions.filter(
    (question) => !answeredQuestionIds.has(question.id),
  );

  await markDeviceSynced(deviceId);
  const refreshedDevice = await getDeviceById(deviceId);

  return {
    serverTime: nowIso(),
    device: serializeDevice(refreshedDevice),
    status: {
      pendingResponses,
      jobs: jobsByStatus,
    },
    matchedLocations: matchedLocations.map((location) => ({
      ...location,
      rules: rulesByLocation.get(location.id) || [],
    })),
    pendingQuestions,
    recentResponses,
  };
}

module.exports = {
  buildSyncPayload,
};
