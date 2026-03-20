const { buildSyncPayload } = require('../services/sync-service');

async function sync(req, res) {
  const result = await buildSyncPayload(req.query || {});
  res.status(200).json(result);
}

module.exports = {
  sync,
};
