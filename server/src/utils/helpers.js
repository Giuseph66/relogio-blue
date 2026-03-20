const { randomUUID } = require('crypto');

function nowIso() {
  return new Date().toISOString();
}

function createId(prefix) {
  return `${prefix}_${randomUUID().replace(/-/g, '')}`;
}

function toNullableNumber(value) {
  if (value === null || value === undefined || value === '') {
    return null;
  }

  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function haversineDistanceMeters(lat1, lon1, lat2, lon2) {
  const values = [lat1, lon1, lat2, lon2];
  if (values.some((value) => !Number.isFinite(value))) {
    return null;
  }

  const earthRadius = 6371000;
  const toRadians = (degrees) => (degrees * Math.PI) / 180;
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadius * c;
}

function normalizeCity(value) {
  return String(value || '').trim().toLowerCase() || null;
}

module.exports = {
  nowIso,
  createId,
  toNullableNumber,
  haversineDistanceMeters,
  normalizeCity,
};
