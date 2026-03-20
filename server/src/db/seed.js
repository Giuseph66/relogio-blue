const { createId, nowIso, normalizeCity } = require('../utils/helpers');

async function seedDatabase(db, enabled) {
  if (!enabled) return;

  const counts = await db.get(`
    SELECT
      (SELECT COUNT(*) FROM locations) AS location_count,
      (SELECT COUNT(*) FROM questions) AS question_count
  `);

  if (counts.location_count > 0 || counts.question_count > 0) {
    return;
  }

  const timestamp = nowIso();
  const locationId = createId('loc');
  const questionId = createId('qst');

  await db.run(
    `
      INSERT INTO locations (
        id, name, city, latitude, longitude, radius_meters, is_active, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
    `,
    [
      locationId,
      'Campus Exemplo',
      normalizeCity('Cuiaba'),
      -15.6014,
      -56.0979,
      150,
      timestamp,
      timestamp,
    ],
  );

  await db.run(
    `
      INSERT INTO location_rules (
        id, location_id, rule_type, rule_value, priority, is_active, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, 1, ?, ?)
    `,
    [
      createId('rule'),
      locationId,
      'notify',
      'Perguntar ao entrar no campus',
      10,
      timestamp,
      timestamp,
    ],
  );

  await db.run(
    `
      INSERT INTO questions (
        id, prompt, location_id, city, status, reactive_enabled, valid_from, valid_until, created_at, updated_at
      ) VALUES (?, ?, ?, ?, 'active', 1, NULL, NULL, ?, ?)
    `,
    [
      questionId,
      'Voce chegou ao local monitorado?',
      locationId,
      normalizeCity('Cuiaba'),
      timestamp,
      timestamp,
    ],
  );

  await db.run(
    `
      INSERT INTO question_options (
        id, question_id, option_id, label, sort_order, created_at
      ) VALUES (?, ?, ?, ?, ?, ?), (?, ?, ?, ?, ?, ?)
    `,
    [
      createId('opt'),
      questionId,
      'SIM',
      'Sim',
      0,
      timestamp,
      createId('opt'),
      questionId,
      'NAO',
      'Nao',
      1,
      timestamp,
    ],
  );
}

module.exports = { seedDatabase };
