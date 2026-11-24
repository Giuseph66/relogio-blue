// Replaces cron: answers every minute, maintenance once a day.
const { spawn } = require('child_process');

function run(action) {
  return new Promise((resolve) => {
    spawn(process.execPath, ['/srv/server/scripts/run-jobs.js', action], { stdio: ['ignore', 'ignore', 'inherit'] })
      .on('exit', resolve);
  });
}

async function every(action, interval) {
  for (;;) {
    await run(action);
    await new Promise((resolve) => setTimeout(resolve, interval));
  }
}

every('process-pending', 60000);
every('maintenance', 24 * 3600000);
