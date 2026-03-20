const { getAdminDashboardData } = require('../services/admin-dashboard-service');

async function getPublicDashboard(req, res) {
  const data = await getAdminDashboardData();
  res.status(200).json(data);
}

module.exports = {
  getPublicDashboard,
};
