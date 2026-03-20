const {
  JOB_BATCH_SIZE,
  STALE_JOB_MINUTES,
  JOB_HISTORY_RETENTION_DAYS,
  MESSAGE_RETENTION_LIMIT,
} = require('../config/env');
const {
  claimPendingJobs,
  completeJob,
  failJob,
  resetStaleJobs,
  pruneFinishedJobs,
  countJobsByStatus,
} = require('../repositories/job-repository');
const {
  getResponseById,
  markResponseProcessed,
  markResponseFailed,
  countPendingResponses,
} = require('../repositories/response-repository');
const { pruneMessagesToLimit } = require('../repositories/message-repository');
const { upsertDevice } = require('../repositories/device-repository');
const { nowIso } = require('../utils/helpers');

async function processPendingResponses(batchSize = JOB_BATCH_SIZE) {
  const jobs = await claimPendingJobs({
    jobType: 'process_response',
    limit: batchSize,
  });

  const processed = [];
  const failed = [];

  for (const job of jobs) {
    try {
      const response = await getResponseById(job.entity_id);
      if (!response) {
        throw new Error('Response not found');
      }

      await upsertDevice({
        id: response.device_id,
        city: response.city,
        latitude: response.latitude,
        longitude: response.longitude,
        status: 'active',
      });

      await markResponseProcessed(response.id, nowIso());
      await completeJob(job.id);
      processed.push(job.id);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown job error';
      await markResponseFailed(job.entity_id, message);
      await failJob(job.id, message, false);
      failed.push({
        jobId: job.id,
        error: message,
      });
    }
  }

  return {
    requestedBatchSize: batchSize,
    claimedJobs: jobs.length,
    processedJobs: processed.length,
    failedJobs: failed.length,
    failures: failed,
  };
}

async function runMaintenance() {
  const staleBefore = new Date(
    Date.now() - STALE_JOB_MINUTES * 60 * 1000,
  ).toISOString();
  const finishedBefore = new Date(
    Date.now() - JOB_HISTORY_RETENTION_DAYS * 24 * 60 * 60 * 1000,
  ).toISOString();

  const [resetCount, prunedJobs, pendingResponses] = await Promise.all([
    resetStaleJobs(staleBefore),
    pruneFinishedJobs(finishedBefore),
    countPendingResponses(),
  ]);

  await pruneMessagesToLimit(MESSAGE_RETENTION_LIMIT);

  return {
    resetStaleJobs: resetCount,
    prunedFinishedJobs: prunedJobs,
    pendingResponses,
    jobStatus: await countJobsByStatus(),
  };
}

module.exports = {
  processPendingResponses,
  runMaintenance,
};
