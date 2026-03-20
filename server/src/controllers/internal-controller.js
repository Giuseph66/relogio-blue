const { JOB_BATCH_SIZE } = require('../config/env');
const { processPendingResponses, runMaintenance } = require('../services/job-service');

async function processPending(req, res) {
  const batchSize = Number(
    req.body?.batchSize || req.query.batchSize || JOB_BATCH_SIZE,
  );
  const result = await processPendingResponses(batchSize);
  res.status(200).json({ ok: true, result });
}

async function maintenance(req, res) {
  const result = await runMaintenance();
  res.status(200).json({ ok: true, result });
}

module.exports = {
  processPending,
  maintenance,
};
