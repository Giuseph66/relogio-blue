const clients = new Set();

function registerClient(req, res, initialMessages) {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
    'Access-Control-Allow-Origin': '*',
  });

  res.write(`event: init\ndata: ${JSON.stringify(initialMessages)}\n\n`);
  clients.add(res);

  const heartbeat = setInterval(() => {
    res.write(`event: ping\ndata: {}\n\n`);
  }, 30000);

  req.on('close', () => {
    clearInterval(heartbeat);
    clients.delete(res);
  });
}

function broadcastMessage(message) {
  const data = `event: message\ndata: ${JSON.stringify(message)}\n\n`;
  for (const client of clients) {
    client.write(data);
  }
}

module.exports = {
  registerClient,
  broadcastMessage,
};
