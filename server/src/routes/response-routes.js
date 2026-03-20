const { Router } = require('express');
const { asyncHandler } = require('../utils/async-handler');
const { requireAppAuth } = require('../middleware/auth');
const { createResponse } = require('../controllers/response-controller');

const router = Router();

router.post('/', requireAppAuth(), asyncHandler(createResponse));

module.exports = { responseRoutes: router };
