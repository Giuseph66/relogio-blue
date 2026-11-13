const { Router } = require('express');
const { asyncHandler } = require('../utils/async-handler');
const { requireAdminApiAuth } = require('../middleware/auth');
const {
  cities,
  publicPlaces,
  validate,
  reverse,
} = require('../controllers/discovery-controller');

const router = Router();

router.use(requireAdminApiAuth);
router.get('/cities', asyncHandler(cities));
router.get('/search', asyncHandler(cities));
router.get('/reverse', asyncHandler(reverse));
router.get('/public-places', asyncHandler(publicPlaces));
router.get('/validate-location', asyncHandler(validate));
router.post('/validate-location', asyncHandler(validate));

module.exports = { discoveryRoutes: router };
