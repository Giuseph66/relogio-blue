const { ingestResponse } = require('../services/response-service');

async function createResponse(req, res) {
  const result = await ingestResponse(req.body || {});
  res.status(result.created ? 201 : 200).json({
    ok: true,
    created: result.created,
    response: result.response,
  });
}

module.exports = {
  createResponse,
};
