const { HttpError } = require('../utils/http-error');

function notFoundHandler(req, res) {
  res.status(404).json({ error: 'not found' });
}

function errorHandler(error, req, res, next) {
  if (res.headersSent) {
    next(error);
    return;
  }

  if (error instanceof HttpError) {
    res.status(error.statusCode).json({
      error: error.message,
      details: error.details,
    });
    return;
  }

  console.error('[server] unexpected error', error);
  res.status(500).json({ error: 'internal server error' });
}

module.exports = {
  notFoundHandler,
  errorHandler,
};
