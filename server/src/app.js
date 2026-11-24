const path = require('path');
const express = require('express');
const cors = require('cors');
const { PUBLIC_DIR, PWA_DIR, TRUST_PROXY } = require('./config/env');
const { router } = require('./routes');
const { notFoundHandler, errorHandler } = require('./middleware/error-handler');

function createApp() {
  const app = express();

  // Real client IP (login rate limit) and protocol (Secure cookies).
  app.set('trust proxy', TRUST_PROXY);
  app.use(cors());
  app.use(express.json({ limit: '1mb' }));
  app.use(express.urlencoded({ extended: true }));

  app.use(router);
  app.use('/app', express.static(PWA_DIR, { index: false, setHeaders(res) {
    res.setHeader('Cache-Control', 'no-cache');
  } }));
  app.get(/^\/app(?:\/.*)?$/, (req, res, next) => {
    // Missing assets must be 404, never HTML masquerading as JavaScript/Wasm.
    if (path.extname(req.path)) return res.status(404).end();
    res.setHeader('Cache-Control', 'no-cache');
    res.sendFile(path.join(PWA_DIR, 'index.html'), (error) => {
      if (error) next(error);
    });
  });
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
