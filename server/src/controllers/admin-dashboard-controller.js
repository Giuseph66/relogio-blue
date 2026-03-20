const { getAdminDashboardData } = require('../services/admin-dashboard-service');

async function getDashboard(req, res) {
  const data = await getAdminDashboardData();
  res.status(200).json(data);
}

module.exports = {
  getDashboard,
};
