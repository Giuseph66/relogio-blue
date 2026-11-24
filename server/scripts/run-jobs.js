// Reuses the backend's env loader; cron never needs tokens in its command line.
const { PORT, INTERNAL_AUTH_TOKEN } = require('../src/config/env');
const action = process.argv[2];
if (!['process-pending', 'maintenance'].includes(action)) {
  console.error('Uso: node scripts/run-jobs.js process-pending|maintenance');
  process.exit(1);
}
const baseUrl = process.env.JOBS_BASE_URL || `http://127.0.0.1:${PORT}`;
fetch(`${baseUrl}/internal/jobs/${action}`, {
  method: 'POST', headers: { Authorization: `Bearer ${INTERNAL_AUTH_TOKEN}` },
  signal: AbortSignal.timeout(60000),
}).then(async response => {
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  console.log(JSON.stringify(await response.json()));
}).catch(error => {
  console.error(`[jobs] ${action}: ${error.message}`);
  process.exitCode = 1;
});
