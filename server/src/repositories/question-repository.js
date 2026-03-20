const { getDb } = require('../db/connection');
const { createId, nowIso, normalizeCity } = require('../utils/helpers');

async function listQuestions() {
  const db = await getDb();
  const questions = await db.all(
    `
      SELECT questions.*, locations.name AS location_name
      FROM questions
      LEFT JOIN locations ON locations.id = questions.location_id
      ORDER BY created_at DESC
    `,
  );

  return hydrateQuestions(questions);
}

async function getQuestionById(id) {
  const db = await getDb();
  const row = await db.get(
    `
      SELECT questions.*, locations.name AS location_name
      FROM questions
      LEFT JOIN locations ON locations.id = questions.location_id
      WHERE questions.id = ?
    `,
    [id],
  );
  if (!row) return null;

  const [question] = await hydrateQuestions([row]);
  return question;
}

async function listActiveQuestions({ city = null, locationIds = [], now = nowIso() }) {
  const db = await getDb();
  const values = [now, now];
  const filters = [
    `status = 'active'`,
    `reactive_enabled = 1`,
    `(valid_from IS NULL OR valid_from <= ?)`,
    `(valid_until IS NULL OR valid_until >= ?)`,
  ];

  if (city) {
    filters.push(`(city IS NULL OR city = ?)`);
    values.push(normalizeCity(city));
  } else {
    filters.push(`city IS NULL`);
  }

  if (locationIds.length) {
    const placeholders = locationIds.map(() => '?').join(', ');
    filters.push(`(location_id IS NULL OR location_id IN (${placeholders}))`);
    values.push(...locationIds);
  } else {
    filters.push(`location_id IS NULL`);
  }

  const rows = await db.all(
    `
      SELECT *
      FROM questions
      WHERE ${filters.join(' AND ')}
      ORDER BY created_at DESC
    `,
    values,
  );

  return hydrateQuestions(rows);
}

async function createQuestion(payload) {
  const db = await getDb();
  const timestamp = nowIso();
  const id = createId('qst');

  await db.run(
    `
      INSERT INTO questions (
        id, prompt, location_id, city, status, reactive_enabled, valid_from, valid_until, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `,
    [
      id,
      payload.prompt,
      payload.locationId || null,
      normalizeCity(payload.city),
      payload.status || 'active',
      payload.reactiveEnabled === false ? 0 : 1,
      payload.validFrom || null,
      payload.validUntil || null,
      timestamp,
      timestamp,
    ],
  );

  if (Array.isArray(payload.options)) {
    await replaceQuestionOptions(id, payload.options);
  }

  return getQuestionById(id);
}

async function updateQuestion(id, payload) {
  const db = await getDb();
  const current = await db.get(`SELECT * FROM questions WHERE id = ?`, [id]);
  if (!current) return null;

  const timestamp = nowIso();
  await db.run(
    `
      UPDATE questions
      SET prompt = ?, location_id = ?, city = ?, status = ?, reactive_enabled = ?, valid_from = ?, valid_until = ?, updated_at = ?
      WHERE id = ?
    `,
    [
      payload.prompt ?? current.prompt,
      payload.locationId === undefined ? current.location_id : payload.locationId,
      normalizeCity(payload.city === undefined ? current.city : payload.city),
      payload.status ?? current.status,
      payload.reactiveEnabled === undefined
        ? current.reactive_enabled
        : payload.reactiveEnabled
          ? 1
          : 0,
      payload.validFrom === undefined ? current.valid_from : payload.validFrom,
      payload.validUntil === undefined ? current.valid_until : payload.validUntil,
      timestamp,
      id,
    ],
  );

  if (Array.isArray(payload.options)) {
    await replaceQuestionOptions(id, payload.options);
  }

  return getQuestionById(id);
}

async function deleteQuestion(id) {
  const db = await getDb();
  const result = await db.run(`DELETE FROM questions WHERE id = ?`, [id]);
  return result.changes > 0;
}

async function listAnsweredQuestionIdsByDevice(deviceId) {
  const db = await getDb();
  const rows = await db.all(
    `
      SELECT DISTINCT question_id AS questionId
      FROM responses
      WHERE device_id = ? AND question_id IS NOT NULL AND status IN ('pending', 'processed')
    `,
    [deviceId],
  );

  return new Set(rows.map((row) => row.questionId));
}

async function hydrateQuestions(rows) {
  if (!rows.length) return [];

  const db = await getDb();
  const ids = rows.map((row) => row.id);
  const placeholders = ids.map(() => '?').join(', ');
  const options = await db.all(
    `
      SELECT *
      FROM question_options
      WHERE question_id IN (${placeholders})
      ORDER BY sort_order ASC, created_at ASC
    `,
    ids,
  );

  const optionsByQuestion = new Map();
  for (const option of options) {
    const items = optionsByQuestion.get(option.question_id) || [];
    items.push({
      id: option.option_id,
      label: option.label,
      sortOrder: option.sort_order,
    });
    optionsByQuestion.set(option.question_id, items);
  }

  return rows.map((row) => ({
    id: row.id,
    prompt: row.prompt,
    locationId: row.location_id,
    locationName: row.location_name || null,
    city: row.city,
    status: row.status,
    reactiveEnabled: Boolean(row.reactive_enabled),
    validFrom: row.valid_from,
    validUntil: row.valid_until,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    options: optionsByQuestion.get(row.id) || [],
  }));
}

async function findQuestionIdByPrefix(prefix) {
  if (!prefix) return null;
  const db = await getDb();
  // Exact match first
  const exact = await db.get(`SELECT id FROM questions WHERE id = ?`, [prefix]);
  if (exact) return exact.id;
  // Prefix match (BLE truncates questionId to 10 chars)
  const like = await db.get(`SELECT id FROM questions WHERE id LIKE ? LIMIT 1`, [`${prefix}%`]);
  return like ? like.id : null;
}

async function countQuestions() {
  const db = await getDb();
  const row = await db.get(`SELECT COUNT(*) AS total FROM questions`);
  return row.total;
}

async function replaceQuestionOptions(questionId, options) {
  const db = await getDb();
  const timestamp = nowIso();

  await db.run(`DELETE FROM question_options WHERE question_id = ?`, [questionId]);

  for (let index = 0; index < options.length; index += 1) {
    const option = options[index];
    await db.run(
      `
        INSERT INTO question_options (
          id, question_id, option_id, label, sort_order, created_at
        ) VALUES (?, ?, ?, ?, ?, ?)
      `,
      [
        createId('opt'),
        questionId,
        option.id,
        option.label,
        option.sortOrder ?? index,
        timestamp,
      ],
    );
  }
}

module.exports = {
  listQuestions,
  getQuestionById,
  listActiveQuestions,
  createQuestion,
  updateQuestion,
  deleteQuestion,
  listAnsweredQuestionIdsByDevice,
  findQuestionIdByPrefix,
  countQuestions,
};
