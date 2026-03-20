const { getDb } = require('../db/connection');
const { createId, nowIso } = require('../utils/helpers');

async function enqueueJob({
  jobType,
  entityType,
  entityId,
  availableAt = nowIso(),
  payload = {},
}) {
  const db = await getDb();
  const timestamp = nowIso();
  const id = createId('job');

  await db.run(
    `
      INSERT INTO jobs (
        id, job_type, entity_type, entity_id, status, attempts, available_at,
        started_at, finished_at, error_message, payload_json, created_at, updated_at
      ) VALUES (?, ?, ?, ?, 'pending', 0, ?, NULL, NULL, NULL, ?, ?, ?)
    `,
    [id, jobType, entityType, entityId, availableAt, JSON.stringify(payload), timestamp, timestamp],
  );

  return id;
}

async function claimPendingJobs({ jobType, limit }) {
  const db = await getDb();
  const now = nowIso();

  await db.exec('BEGIN IMMEDIATE TRANSACTION');
  try {
    const jobs = await db.all(
      `
        SELECT *
        FROM jobs
        WHERE status = 'pending' AND available_at <= ? AND job_type = ?
        ORDER BY created_at ASC
        LIMIT ?
      `,
      [now, jobType, limit],
    );

    for (const job of jobs) {
      await db.run(
        `
          UPDATE jobs
          SET status = 'processing', attempts = attempts + 1, started_at = ?, updated_at = ?
          WHERE id = ?
        `,
        [now, now, job.id],
      );
    }

    await db.exec('COMMIT');
    return jobs.map((job) => ({
      ...job,
      payload: JSON.parse(job.payload_json || '{}'),
    }));
  } catch (error) {
    await db.exec('ROLLBACK');
    throw error;
  }
}

async function completeJob(id) {
  const db = await getDb();
  const timestamp = nowIso();
  await db.run(
    `
      UPDATE jobs
      SET status = 'done', finished_at = ?, updated_at = ?, error_message = NULL
      WHERE id = ?
    `,
    [timestamp, timestamp, id],
  );
}

async function failJob(id, errorMessage, requeue = false) {
  const db = await getDb();
  const timestamp = nowIso();
  await db.run(
    `
      UPDATE jobs
      SET status = ?, finished_at = ?, updated_at = ?, error_message = ?
      WHERE id = ?
    `,
    [requeue ? 'pending' : 'failed', timestamp, timestamp, errorMessage, id],
  );
}

async function resetStaleJobs(staleBeforeIso) {
  const db = await getDb();
  const timestamp = nowIso();
  const result = await db.run(
    `
      UPDATE jobs
      SET status = 'pending', updated_at = ?, started_at = NULL, error_message = 'Reset after stale processing window'
      WHERE status = 'processing' AND started_at IS NOT NULL AND started_at < ?
    `,
    [timestamp, staleBeforeIso],
  );
  return result.changes || 0;
}

async function pruneFinishedJobs(finishedBeforeIso) {
  const db = await getDb();
  const result = await db.run(
    `
      DELETE FROM jobs
      WHERE status IN ('done', 'failed') AND finished_at IS NOT NULL AND finished_at < ?
    `,
    [finishedBeforeIso],
  );
  return result.changes || 0;
}

async function countJobsByStatus() {
  const db = await getDb();
  const rows = await db.all(
    `
      SELECT status, COUNT(*) AS total
      FROM jobs
      GROUP BY status
    `,
  );

  return rows.reduce((acc, row) => {
    acc[row.status] = row.total;
    return acc;
  }, {});
}

module.exports = {
  enqueueJob,
  claimPendingJobs,
  completeJob,
  failJob,
  resetStaleJobs,
  pruneFinishedJobs,
  countJobsByStatus,
};
