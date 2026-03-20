const { Router } = require('express');
const { asyncHandler } = require('../utils/async-handler');
const { requireAdminApiAuth } = require('../middleware/auth');
const { getDashboard } = require('../controllers/admin-dashboard-controller');

const router = Router();

router.use(requireAdminApiAuth);
router.get('/', asyncHandler(getDashboard));

module.exports = { adminDashboardRoutes: router };
