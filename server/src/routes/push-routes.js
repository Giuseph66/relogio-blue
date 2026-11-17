const { Router } = require('express');
const { asyncHandler } = require('../utils/async-handler');
const { requireAppAuth, requireAdminApiAuth } = require('../middleware/auth');
const controller = require('../controllers/push-controller');
const pushRoutes = Router();
const adminPushRoutes = Router();

pushRoutes.get('/config', controller.configuration);
pushRoutes.use(requireAppAuth());
pushRoutes.post('/subscription', asyncHandler(controller.subscribe));
pushRoutes.delete('/subscription', asyncHandler(controller.unsubscribe));
pushRoutes.post('/test', asyncHandler(controller.test));
adminPushRoutes.use(requireAdminApiAuth);
adminPushRoutes.get('/status', asyncHandler(controller.status));
adminPushRoutes.post('/send', asyncHandler(controller.broadcast));
module.exports = { pushRoutes, adminPushRoutes };
