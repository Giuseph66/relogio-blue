const { MESSAGE_RETENTION_LIMIT } = require('../config/env');
const { createMessage, listRecentMessages, pruneMessagesToLimit } = require('../repositories/message-repository');
const { upsertDevice } = require('../repositories/device-repository');
const { broadcastMessage } = require('./sse-service');
const { createId, nowIso } = require('../utils/helpers');

function isTickMessage(content) {
  return String(content || '').toLowerCase().includes('tick');
}

async function ingestMessage(payload) {
  const timestamp = nowIso();
  const message = {
    id: createId('msg'),
    content: String(payload.content),
    deviceId: payload.deviceId || null,
    deviceName: payload.deviceName || null,
    source: payload.source || 'relay',
    timestamp: payload.timestamp || timestamp,
    receivedAt: timestamp,
    metadata: payload.metadata || {},
  };

  if (message.deviceId) {
    await upsertDevice({
      id: message.deviceId,
      name: message.deviceName,
    });
  }

  await createMessage(message);
  await pruneMessagesToLimit(MESSAGE_RETENTION_LIMIT);

  if (!isTickMessage(message.content)) {
    broadcastMessage(message);
  }

  return message;
}

async function getRecentMessages(limit = 200) {
  const messages = await listRecentMessages(limit);
  return messages.filter((message) => !isTickMessage(message.content));
}

module.exports = {
  ingestMessage,
  getRecentMessages,
  isTickMessage,
};
