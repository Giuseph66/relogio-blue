const { Router } = require('express');
const { requireAppAuth } = require('../middleware/auth');
const { asyncHandler } = require('../utils/async-handler');
const { HttpError } = require('../utils/http-error');
const { NOMINATIM_BASE_URL } = require('../config/env');

const router = Router();
const cache = new Map();
let queue = Promise.resolve();
let lastRequest = 0;

router.get('/', requireAppAuth(), asyncHandler(async (req, res) => {
  const query = String(req.query.q || '').trim();
  const url = new URL(query ? '/search' : '/reverse', NOMINATIM_BASE_URL);
  url.searchParams.set('format', 'jsonv2');
  url.searchParams.set('addressdetails', '1');
  if (query) {
    if (query.length < 3 || query.length > 200) throw new HttpError(400, 'invalid query');
    url.searchParams.set('q', query);
    url.searchParams.set('limit', '5');
  } else {
    const lat = Number(req.query.lat);
    const lon = Number(req.query.lon);
    if (!req.query.lat || !req.query.lon || !Number.isFinite(lat) || !Number.isFinite(lon) ||
        Math.abs(lat) > 90 || Math.abs(lon) > 180) throw new HttpError(400, 'invalid coordinates');
    url.searchParams.set('lat', lat.toFixed(4));
    url.searchParams.set('lon', lon.toFixed(4));
  }
  const key = url.toString();
  const cached = cache.get(key);
  if (cached && Date.now() - cached.time < 86400000) return res.json(cached.data);
  // Nominatim public endpoint: serialize requests, at most one per second.
  const result = queue.then(async () => {
    const hit = cache.get(key);
    if (hit && Date.now() - hit.time < 86400000) return hit.data;
    await new Promise((resolve) => setTimeout(resolve, Math.max(0, 1100 - (Date.now() - lastRequest))));
    lastRequest = Date.now();
    const response = await fetch(url, {
      headers: { 'User-Agent': 'GeoNexo/1.0 (relogio-blutu)', 'Accept-Language': 'pt-BR', Accept: 'application/json' },
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new HttpError(502, 'geocoding unavailable');
    const body = await response.json();
    const data = Array.isArray(body) ? body : body.error ? [] : [body];
    if (cache.size >= 256) cache.delete(cache.keys().next().value);
    cache.set(key, { time: Date.now(), data });
    return data;
  });
  queue = result.catch(() => {});
  res.json(await result);
}));

module.exports = { geocodingRoutes: router };
