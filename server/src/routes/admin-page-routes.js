const { Router } = require('express');
const {
  requireAdminPageAuth,
  requireGuestAdminPage,
} = require('../middleware/auth');
const {
  sendLoginPage,
  sendAdminPanel,
} = require('../controllers/admin-page-controller');

const router = Router();

router.get('/login', requireGuestAdminPage, sendLoginPage);
router.get('/', requireAdminPageAuth, sendAdminPanel);
router.get('/config', requireAdminPageAuth, sendAdminPanel);
router.get('/dashboard', requireAdminPageAuth, sendAdminPanel);

module.exports = { adminPageRoutes: router };
