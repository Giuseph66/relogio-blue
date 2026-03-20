const { PORT, DB_PATH } = require('./src/config/env');
const { initDatabase } = require('./src/db/connection');
const { createApp } = require('./src/app');

async function bootstrap() {
  await initDatabase();

  const app = createApp();
  app.listen(PORT, () => {
    console.log(`[BLE Server] running at http://localhost:${PORT}`);
    console.log(`[BLE Server] sqlite db at ${DB_PATH}`);
  });
}

bootstrap().catch((error) => {
  console.error('[BLE Server] failed to start', error);
  process.exit(1);
});
