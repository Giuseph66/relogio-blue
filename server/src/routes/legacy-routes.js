const { Router } = require('express');
const { asyncHandler } = require('../utils/async-handler');
const { listMessages, createMessage, streamMessages } = require('../controllers/message-controller');
const { requireLegacyMessagePostAuth } = require('../middleware/auth');

const router = Router();

router.get('/messages', asyncHandler(listMessages));
router.post('/messages', requireLegacyMessagePostAuth(), asyncHandler(createMessage));
router.get('/events', asyncHandler(streamMessages));

module.exports = { legacyRoutes: router };
