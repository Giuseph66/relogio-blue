const path = require('path');
const express = require('express');
const cors = require('cors');
const { PUBLIC_DIR } = require('./config/env');
const { router } = require('./routes');
const { notFoundHandler, errorHandler } = require('./middleware/error-handler');

function createApp() {
  const app = express();

  app.use(cors());
  app.use(express.json({ limit: '1mb' }));
  app.use(express.urlencoded({ extended: true }));

  app.use(router);
  app.use(express.static(PUBLIC_DIR));

  app.get(/^(?!\/api|\/internal|\/health|\/admin).*/, (req, res, next) => {
    if (req.path === '/events') {
      next();
      return;
    }
    res.sendFile(path.join(PUBLIC_DIR, 'index.html'));
  });

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}

module.exports = { createApp };
