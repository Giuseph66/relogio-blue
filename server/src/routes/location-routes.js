const { Router } = require('express');
const { asyncHandler } = require('../utils/async-handler');
const { requireAppAuth } = require('../middleware/auth');
const { resolve, listPublic } = require('../controllers/location-controller');

const router = Router();

// Public: returns all active locations (no auth required)
router.get('/', asyncHandler(listPublic));

router.get('/resolve', requireAppAuth(), asyncHandler(resolve));
router.post('/resolve', requireAppAuth(), asyncHandler(resolve));

module.exports = { locationRoutes: router };
