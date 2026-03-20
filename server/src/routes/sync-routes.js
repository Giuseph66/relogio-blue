const { Router } = require('express');
const { asyncHandler } = require('../utils/async-handler');
const { requireAppAuth } = require('../middleware/auth');
const { sync } = require('../controllers/sync-controller');

const router = Router();

router.get('/', requireAppAuth(), asyncHandler(sync));

module.exports = { syncRoutes: router };
