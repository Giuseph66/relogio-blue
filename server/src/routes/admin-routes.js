const { Router } = require('express');
const { asyncHandler } = require('../utils/async-handler');
const { requireAdminApiAuth } = require('../middleware/auth');
const {
  getCatalog,
  getLocations,
  postLocation,
  putLocation,
  removeLocation,
  getQuestions,
  postQuestion,
  putQuestion,
  removeQuestion,
} = require('../controllers/admin-controller');

const router = Router();

router.use(requireAdminApiAuth);

router.get('/catalog', asyncHandler(getCatalog));
router.get('/locations', asyncHandler(getLocations));
router.post('/locations', asyncHandler(postLocation));
router.put('/locations/:locationId', asyncHandler(putLocation));
router.delete('/locations/:locationId', asyncHandler(removeLocation));

router.get('/questions', asyncHandler(getQuestions));
router.post('/questions', asyncHandler(postQuestion));
router.put('/questions/:questionId', asyncHandler(putQuestion));
router.delete('/questions/:questionId', asyncHandler(removeQuestion));

module.exports = { adminRoutes: router };
