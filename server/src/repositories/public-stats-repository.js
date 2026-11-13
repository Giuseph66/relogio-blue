const { getDb } = require('../db/connection');

/*
 * Aggregated, anonymised data for the public dashboard.
 * Never expose device ids/names, response coordinates or error messages here.
 */

async function getPublicSummary(tzModifier = '+0 minutes') {
  const db = await getDb();
  const [responses, locations, devices] = await Promise.all([
    db.get(`
      SELECT
        COUNT(*) AS totalResponses,
        SUM(CASE WHEN DATE(received_at, ?) = DATE('now', ?) THEN 1 ELSE 0 END) AS responsesToday,
        SUM(CASE WHEN received_at >= DATETIME('now', '-7 day') THEN 1 ELSE 0 END) AS responsesWeek
      FROM responses
    `, [tzModifier, tzModifier]),
    db.get(`SELECT COUNT(*) AS total FROM locations WHERE is_active = 1`),
    db.get(`
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN last_seen_at >= ? THEN 1 ELSE 0 END) AS activeToday
      FROM devices
    `, [new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()]),
  ]);

  return {
    totalResponses: responses.totalResponses || 0,
    responsesToday: responses.responsesToday || 0,
    responsesWeek: responses.responsesWeek || 0,
    activeLocations: locations.total || 0,
    devices: devices.total || 0,
    devicesActiveToday: devices.activeToday || 0,
  };
}

async function listPublicLocations() {
  const db = await getDb();
  return db.all(`
    SELECT locations.id,
           locations.name,
           locations.city,
           locations.latitude,
           locations.longitude,
           locations.radius_meters AS radiusMeters,
           COUNT(responses.id) AS responses
    FROM locations
    LEFT JOIN questions ON questions.location_id = locations.id
    LEFT JOIN responses ON responses.question_id = questions.id
    WHERE locations.is_active = 1
      AND locations.latitude IS NOT NULL
      AND locations.longitude IS NOT NULL
    GROUP BY locations.id
    ORDER BY locations.name ASC
  `);
}

async function listQuestionResults() {
  const db = await getDb();
  const rows = await db.all(`
    SELECT questions.id AS questionId,
           questions.prompt,
           questions.location_id AS locationId,
           locations.name AS locationName,
           locations.city,
           question_options.option_id AS optionId,
           question_options.label,
           question_options.sort_order AS sortOrder,
           (
             SELECT COUNT(*)
             FROM responses
             WHERE responses.question_id = questions.id
               AND responses.answer_id = question_options.option_id
           ) AS total,
           (
             SELECT MAX(received_at)
             FROM responses
             WHERE responses.question_id = questions.id
           ) AS lastResponseAt
    FROM questions
    JOIN question_options ON question_options.question_id = questions.id
    LEFT JOIN locations ON locations.id = questions.location_id
    WHERE questions.status = 'active'
    ORDER BY questions.created_at DESC, question_options.sort_order ASC
  `);

  const byQuestion = new Map();
  for (const row of rows) {
    let item = byQuestion.get(row.questionId);
    if (!item) {
      item = {
        questionId: row.questionId,
        prompt: row.prompt,
        locationId: row.locationId,
        locationName: row.locationName,
        city: row.city,
        lastResponseAt: row.lastResponseAt,
        total: 0,
        options: [],
      };
      byQuestion.set(row.questionId, item);
    }
    item.options.push({ id: row.optionId, label: row.label, total: row.total });
    item.total += row.total;
  }

  // Questions with answers first, most answered on top.
  return [...byQuestion.values()].sort(
    (a, b) => b.total - a.total || String(b.lastResponseAt || '').localeCompare(String(a.lastResponseAt || '')),
  );
}

async function listRecentPublicResponses(limit = 20) {
  const db = await getDb();
  return db.all(`
    SELECT responses.id,
           responses.received_at AS receivedAt,
           COALESCE(responses.answer_text, question_options.label, responses.answer_id) AS answer,
           questions.prompt AS questionPrompt,
           locations.name AS locationName,
           COALESCE(responses.city, locations.city) AS city
    FROM responses
    LEFT JOIN questions ON questions.id = responses.question_id
    LEFT JOIN locations ON locations.id = questions.location_id
    LEFT JOIN question_options
      ON question_options.question_id = responses.question_id
     AND question_options.option_id = responses.answer_id
    ORDER BY responses.received_at DESC
    LIMIT ?
  `, [limit]);
}

async function listPublicVolumeByDay(days = 14, tzModifier = '+0 minutes') {
  const db = await getDb();
  return db.all(`
    SELECT DATE(received_at, ?) AS day, COUNT(*) AS total
    FROM responses
    WHERE DATE(received_at, ?) >= DATE('now', ?, ?)
    GROUP BY day
    ORDER BY day ASC
  `, [tzModifier, tzModifier, tzModifier, `-${days - 1} day`]);
}

async function listPublicTopCities(limit = 6) {
  const db = await getDb();
  return db.all(`
    SELECT city, COUNT(*) AS total
    FROM responses
    WHERE city IS NOT NULL AND city != ''
    GROUP BY city
    ORDER BY total DESC, city ASC
    LIMIT ?
  `, [limit]);
}

/** Full anonymised response history for open-data export (no device, no coordinates). */
async function listAllPublicResponses(limit = 50000) {
  const db = await getDb();
  return db.all(`
    SELECT responses.received_at AS receivedAt,
           locations.name AS locationName,
           COALESCE(responses.city, locations.city) AS city,
           questions.prompt AS questionPrompt,
           COALESCE(responses.answer_text, question_options.label, responses.answer_id) AS answer
    FROM responses
    LEFT JOIN questions ON questions.id = responses.question_id
    LEFT JOIN locations ON locations.id = questions.location_id
    LEFT JOIN question_options
      ON question_options.question_id = responses.question_id
     AND question_options.option_id = responses.answer_id
    ORDER BY responses.received_at DESC
    LIMIT ?
  `, [limit]);
}

module.exports = {
  listAllPublicResponses,
  getPublicSummary,
  listPublicLocations,
  listQuestionResults,
  listRecentPublicResponses,
  listPublicVolumeByDay,
  listPublicTopCities,
};
