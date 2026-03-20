const { DB_PATH } = require('../config/env');

function health(req, res) {
  res.status(200).json({
    ok: true,
    service: 'relogio-blutu-server',
    dbPath: DB_PATH,
    timestamp: new Date().toISOString(),
  });
}

module.exports = { health };
