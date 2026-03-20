const { getDb } = require('../db/connection');

async function createMessage(message) {
  const db = await getDb();
  await db.run(
    `
      INSERT INTO message_events (
        id, content, device_id, device_name, source, timestamp, received_at, metadata_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `,
    [
      message.id,
      message.content,
      message.deviceId,
      message.deviceName,
      message.source,
      message.timestamp,
      message.receivedAt,
      JSON.stringify(message.metadata || {}),
    ],
  );
}

async function listRecentMessages(limit = 200) {
  const db = await getDb();
  const rows = await db.all(
    `
      SELECT id, content, device_id AS deviceId, device_name AS deviceName, source,
             timestamp, received_at AS receivedAt, metadata_json AS metadataJson
      FROM message_events
      ORDER BY received_at DESC
      LIMIT ?
    `,
    [limit],
  );

  return rows.map((row) => ({
    id: row.id,
    content: row.content,
    deviceId: row.deviceId,
    deviceName: row.deviceName,
    source: row.source,
    timestamp: row.timestamp,
    receivedAt: row.receivedAt,
    metadata: JSON.parse(row.metadataJson || '{}'),
  }));
}

async function pruneMessagesToLimit(limit) {
  const db = await getDb();
  await db.run(
    `
      DELETE FROM message_events
      WHERE id NOT IN (
        SELECT id
        FROM message_events
        ORDER BY received_at DESC
        LIMIT ?
      )
    `,
    [limit],
  );
}

module.exports = {
  createMessage,
  listRecentMessages,
  pruneMessagesToLimit,
};
