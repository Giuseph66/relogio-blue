const { Router } = require('express');
const { health } = require('../controllers/health-controller');
const { streamMessages } = require('../controllers/message-controller');
const { getPublicDashboard } = require('../controllers/public-dashboard-controller');
const { asyncHandler } = require('../utils/async-handler');
const { legacyRoutes } = require('./legacy-routes');
const { locationRoutes } = require('./location-routes');
const { responseRoutes } = require('./response-routes');
const { syncRoutes } = require('./sync-routes');
const { adminPageRoutes } = require('./admin-page-routes');
const { adminAuthRoutes } = require('./admin-auth-routes');
const { adminRoutes } = require('./admin-routes');
const { adminDashboardRoutes } = require('./admin-dashboard-routes');
const { discoveryRoutes } = require('./discovery-routes');
const { internalRoutes } = require('./internal-routes');

const router = Router();

router.get('/health', health);
router.get('/events', asyncHandler(streamMessages));
router.get('/api/public/dashboard', asyncHandler(getPublicDashboard));
router.use('/admin', adminPageRoutes);
router.use('/api', legacyRoutes);
router.use('/api/admin/auth', adminAuthRoutes);
router.use('/api/location', locationRoutes);
router.use('/api/responses', responseRoutes);
router.use('/api/sync', syncRoutes);
router.use('/api/admin', adminRoutes);
router.use('/api/admin/dashboard', adminDashboardRoutes);
router.use('/api/admin/discovery', discoveryRoutes);
router.use('/internal/jobs', internalRoutes);

module.exports = { router };
