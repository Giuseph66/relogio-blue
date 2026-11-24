const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const sqlite3 = require('sqlite3');
const { open } = require('sqlite');
const { DB_PATH, SEED_SAMPLE_DATA } = require('../config/env');
const { schema } = require('./schema');
const { seedDatabase } = require('./seed');

let dbPromise;

async function initDatabase() {
  if (!dbPromise) {
    dbPromise = (async () => {
      fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });

      const db = await open({
        filename: DB_PATH,
        driver: sqlite3.Database,
      });

      await db.exec(schema);
      const optionColumns = await db.all('PRAGMA table_info(question_options)');
      if (!optionColumns.some((column) => column.name === 'quick_reply')) {
        await db.exec(`
          BEGIN IMMEDIATE;
          ALTER TABLE question_options ADD COLUMN quick_reply INTEGER NOT NULL DEFAULT 0;
          UPDATE question_options SET quick_reply = 1 WHERE sort_order < 2;
          COMMIT;
        `);
      }
      // One answer per device and question. NULL (administrators and answers from
      // before this rule) never conflicts.
      const responseColumns = await db.all('PRAGMA table_info(responses)');
      if (!responseColumns.some((column) => column.name === 'claim_key')) {
        await db.exec('ALTER TABLE responses ADD COLUMN claim_key TEXT');
      }
      await db.exec('CREATE UNIQUE INDEX IF NOT EXISTS idx_responses_claim ON responses(claim_key)');
      await db.run(
        "INSERT INTO app_settings (key, value) VALUES ('device_claim_secret', ?) ON CONFLICT(key) DO NOTHING",
        [crypto.randomBytes(32).toString('hex')],
      );
      await seedDatabase(db, SEED_SAMPLE_DATA);
      return db;
    })();
  }

  return dbPromise;
}

async function getDb() {
  return initDatabase();
}

module.exports = {
  initDatabase,
  getDb,
};
