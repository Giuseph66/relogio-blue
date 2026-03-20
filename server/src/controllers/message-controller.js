const { getRecentMessages, ingestMessage } = require('../services/message-service');
const { registerClient } = require('../services/sse-service');

async function listMessages(req, res) {
  const messages = await getRecentMessages(Number(req.query.limit || 200));
  res.status(200).json({ messages });
}

async function createMessage(req, res) {
  const message = await ingestMessage(req.body || {});
  res.status(201).json({ ok: true, message });
}

async function streamMessages(req, res) {
  const messages = await getRecentMessages(200);
  registerClient(req, res, messages);
}

module.exports = {
  listMessages,
  createMessage,
  streamMessages,
};
