const { getDb } = require('../db/connection');

async function createResponse(response) {
  const db = await getDb();
  await db.run(
    `
      INSERT INTO responses (
        id, external_id, device_id, question_id, answer_id, answer_text, city, latitude,
        longitude, status, raw_payload_json, submitted_at, received_at, processed_at, error_message
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `,
    [
      response.id,
      response.externalId,
      response.deviceId,
      response.questionId,
      response.answerId,
      response.answerText,
      response.city,
      response.latitude,
      response.longitude,
      response.status,
      JSON.stringify(response.rawPayload),
      response.submittedAt,
      response.receivedAt,
      response.processedAt,
      response.errorMessage,
    ],
  );
}

async function getResponseByExternalId(externalId) {
  const db = await getDb();
  return db.get(`SELECT * FROM responses WHERE external_id = ?`, [externalId]);
}

async function getResponseById(id) {
  const db = await getDb();
  return db.get(`SELECT * FROM responses WHERE id = ?`, [id]);
}

async function markResponseProcessed(id, processedAt) {
  const db = await getDb();
  await db.run(
    `
      UPDATE responses
      SET status = 'processed', processed_at = ?, error_message = NULL
      WHERE id = ?
    `,
    [processedAt, id],
  );
}

async function markResponseFailed(id, errorMessage) {
  const db = await getDb();
  await db.run(
    `
      UPDATE responses
      SET status = 'failed', error_message = ?
      WHERE id = ?
    `,
    [errorMessage, id],
  );
}

async function listRecentResponsesByDevice(deviceId, limit = 20) {
  const db = await getDb();
  return db.all(
    `
      SELECT id, external_id AS externalId, device_id AS deviceId, question_id AS questionId,
             answer_id AS answerId, answer_text AS answerText, city, latitude, longitude,
             status, submitted_at AS submittedAt, received_at AS receivedAt, processed_at AS processedAt
      FROM responses
      WHERE device_id = ?
      ORDER BY received_at DESC
      LIMIT ?
    `,
    [deviceId, limit],
  );
}

async function countPendingResponses() {
  const db = await getDb();
  const row = await db.get(
    `SELECT COUNT(*) AS total FROM responses WHERE status = 'pending'`,
  );
  return row.total;
}

async function getResponseStatusCounts() {
  const db = await getDb();
  const rows = await db.all(
    `
      SELECT status, COUNT(*) AS total
      FROM responses
      GROUP BY status
    `,
  );

  return rows.reduce((acc, row) => {
    acc[row.status] = row.total;
    return acc;
  }, {});
}

async function getResponseSummary() {
  const db = await getDb();
  return db.get(
    `
      SELECT
        COUNT(*) AS totalResponses,
        SUM(CASE WHEN status = 'processed' THEN 1 ELSE 0 END) AS processedResponses,
        SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) AS pendingResponses,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failedResponses,
        SUM(CASE WHEN DATE(received_at) = DATE('now') THEN 1 ELSE 0 END) AS responsesToday
      FROM responses
    `,
  );
}

async function listRecentResponsesDetailed(limit = 30) {
  const db = await getDb();
  return db.all(
    `
      SELECT responses.id,
             responses.external_id AS externalId,
             responses.device_id AS deviceId,
             devices.name AS deviceName,
             responses.question_id AS questionId,
             questions.prompt AS questionPrompt,
             questions.location_id AS locationId,
             locations.name AS locationName,
             responses.answer_id AS answerId,
             responses.answer_text AS answerText,
             responses.city,
             responses.latitude,
             responses.longitude,
             responses.status,
             responses.submitted_at AS submittedAt,
             responses.received_at AS receivedAt,
             responses.processed_at AS processedAt,
             responses.error_message AS errorMessage
      FROM responses
      LEFT JOIN devices ON devices.id = responses.device_id
      LEFT JOIN questions ON questions.id = responses.question_id
      LEFT JOIN locations ON locations.id = questions.location_id
      ORDER BY responses.received_at DESC
      LIMIT ?
    `,
    [limit],
  );
}

async function listResponseVolumeByDay(days = 7) {
  const db = await getDb();
  return db.all(
    `
      SELECT DATE(received_at) AS day, COUNT(*) AS total
      FROM responses
      WHERE received_at >= DATETIME('now', ?)
      GROUP BY DATE(received_at)
      ORDER BY day ASC
    `,
    [`-${days} day`],
  );
}

async function listTopResponseCities(limit = 6) {
  const db = await getDb();
  return db.all(
    `
      SELECT city, COUNT(*) AS total
      FROM responses
      WHERE city IS NOT NULL AND city != ''
      GROUP BY city
      ORDER BY total DESC, city ASC
      LIMIT ?
    `,
    [limit],
  );
}

module.exports = {
  createResponse,
  getResponseByExternalId,
  getResponseById,
  markResponseProcessed,
  markResponseFailed,
  listRecentResponsesByDevice,
  countPendingResponses,
  getResponseStatusCounts,
  getResponseSummary,
  listRecentResponsesDetailed,
  listResponseVolumeByDay,
  listTopResponseCities,
};
