const { Router } = require('express');
const { asyncHandler } = require('../utils/async-handler');
const { requireInternalAuth } = require('../middleware/auth');
const { processPending, maintenance } = require('../controllers/internal-controller');

const router = Router();

router.use(requireInternalAuth);

router.get('/process-pending', asyncHandler(processPending));
router.post('/process-pending', asyncHandler(processPending));
router.get('/maintenance', asyncHandler(maintenance));
router.post('/maintenance', asyncHandler(maintenance));

module.exports = { internalRoutes: router };
