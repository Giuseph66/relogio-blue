const path = require('path');
const { VIEWS_DIR } = require('../config/env');

function sendLoginPage(req, res) {
  res.sendFile(path.join(VIEWS_DIR, 'admin-login.html'));
}

function sendAdminPanel(req, res) {
  res.sendFile(path.join(VIEWS_DIR, 'admin-panel.html'));
}

module.exports = {
  sendLoginPage,
  sendAdminPanel,
};
