const {
  searchCities,
  searchPublicPlaces,
  validateLocation,
  reverseGeocode,
} = require('../services/discovery-service');

async function cities(req, res) {
  const viewbox = /^-?[\d.]+(,-?[\d.]+){3}$/.test(String(req.query.viewbox || ''))
    ? String(req.query.viewbox)
    : null;
  const results = await searchCities(req.query.query || req.query.q, {
    viewbox,
    limit: viewbox ? 8 : 6,
  });
  res.status(200).json({ results });
}

async function publicPlaces(req, res) {
  const results = await searchPublicPlaces(req.query);
  res.status(200).json({ results });
}

async function validate(req, res) {
  const payload = req.method === 'GET' ? req.query : req.body;
  const result = await validateLocation(payload);
  res.status(200).json(result);
}

async function reverse(req, res) {
  const result = await reverseGeocode(req.query);
  res.status(200).json(result);
}

module.exports = {
  cities,
  reverse,
  publicPlaces,
  validate,
};
