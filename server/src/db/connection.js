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
