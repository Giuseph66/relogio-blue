const {
  searchCities,
  searchPublicPlaces,
  validateLocation,
} = require('../services/discovery-service');

async function cities(req, res) {
  const results = await searchCities(req.query.query || req.query.q);
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

module.exports = {
  cities,
  publicPlaces,
  validate,
};
