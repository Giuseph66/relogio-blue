const { countDevices, listRecentDevices } = require('../repositories/device-repository');
const { countLocations } = require('../repositories/catalog-repository');
const { countQuestions } = require('../repositories/question-repository');
const {
  getResponseSummary,
  getResponseStatusCounts,
  listRecentResponsesDetailed,
  listResponseVolumeByDay,
  listTopResponseCities,
} = require('../repositories/response-repository');

async function getAdminDashboardData() {
  const [
    devicesCount,
    locationsCount,
    questionsCount,
    responseSummary,
    responseStatusCounts,
    recentResponses,
    volumeByDay,
    topCities,
    recentDevices,
  ] = await Promise.all([
    countDevices(),
    countLocations(),
    countQuestions(),
    getResponseSummary(),
    getResponseStatusCounts(),
    listRecentResponsesDetailed(25),
    listResponseVolumeByDay(10),
    listTopResponseCities(8),
    listRecentDevices(8),
  ]);

  return {
    summary: {
      devicesCount,
      locationsCount,
      questionsCount,
      totalResponses: responseSummary.totalResponses || 0,
      processedResponses: responseSummary.processedResponses || 0,
      pendingResponses: responseSummary.pendingResponses || 0,
      failedResponses: responseSummary.failedResponses || 0,
      responsesToday: responseSummary.responsesToday || 0,
    },
    responseStatusCounts,
    volumeByDay,
    topCities,
    recentDevices,
    recentResponses,
  };
}

module.exports = {
  getAdminDashboardData,
};
