const { Router } = require('express');
const { asyncHandler } = require('../utils/async-handler');
const { requireAccount } = require('../middleware/auth');
const controller = require('../controllers/account-controller');

const router = Router();

router.use((req, res, next) => {
  res.set('Cache-Control', 'no-store');
  next();
});
router.post('/register', asyncHandler(controller.register));
router.post('/login', asyncHandler(controller.login));
router.get('/session', asyncHandler(controller.session));
router.post('/logout', asyncHandler(controller.logout));
router.delete('/', requireAccount, asyncHandler(controller.remove));
router.get('/profile', requireAccount, asyncHandler(controller.getProfile));
router.put('/profile', requireAccount, asyncHandler(controller.putProfile));

module.exports = { accountRoutes: router };
