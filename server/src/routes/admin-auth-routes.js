const { Router } = require('express');
const { asyncHandler } = require('../utils/async-handler');
const {
  login,
  logout,
  session,
} = require('../controllers/admin-auth-controller');

const router = Router();

router.post('/login', asyncHandler(login));
router.post('/logout', asyncHandler(logout));
router.get('/session', asyncHandler(session));

module.exports = { adminAuthRoutes: router };
