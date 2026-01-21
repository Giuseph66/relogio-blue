const http = require('http');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');

const PORT = Number(process.env.PORT || 3001);
const PUBLIC_DIR = path.join(__dirname, 'public');
const MAX_MESSAGES = 200;

const messages = [];
const clients = new Set();

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Access-Control-Allow-Origin': '*',
  });
  res.end(body);
}

function sendText(res, statusCode, payload, contentType = 'text/plain; charset=utf-8') {
  res.writeHead(statusCode, {
    'Content-Type': contentType,
    'Content-Length': Buffer.byteLength(payload),
  });
  res.end(payload);
}

function addMessage(message) {
  // Filtrar mensagens que contêm "tick" (case insensitive)
  const content = String(message.content || '').toLowerCase();
  if (content.includes('tick')) {
    return; // Ignorar mensagens com "tick"
  }

  messages.push(message);
  if (messages.length > MAX_MESSAGES) {
    messages.shift();
  }

  const data = `event: message\ndata: ${JSON.stringify(message)}\n\n`;
  for (const client of clients) {
    client.write(data);
  }
}

function handleEvents(req, res) {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
    'Access-Control-Allow-Origin': '*',
  });

  res.write(`event: init\ndata: ${JSON.stringify(messages)}\n\n`);
  clients.add(res);

  req.on('close', () => {
    clients.delete(res);
  });
}

function handleApi(req, res, pathname) {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    });
    res.end();
    return;
  }

  if (pathname === '/api/messages' && req.method === 'GET') {
    // Filtrar mensagens que contêm "tick" antes de retornar
    const filteredMessages = messages.filter(msg => {
      const content = String(msg.content || '').toLowerCase();
      return !content.includes('tick');
    });
    sendJson(res, 200, { messages: filteredMessages });
    return;
  }

  if (pathname === '/api/messages' && req.method === 'POST') {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
      if (body.length > 1024 * 1024) {
        req.destroy();
      }
    });
    req.on('end', () => {
      try {
        const payload = JSON.parse(body || '{}');
        if (!payload.content) {
          sendJson(res, 400, { error: 'content is required' });
          return;
        }

        const message = {
          id: `msg_${Date.now()}_${Math.random().toString(16).slice(2, 8)}`,
          content: String(payload.content),
          deviceId: payload.deviceId || null,
          deviceName: payload.deviceName || null,
          timestamp: payload.timestamp || new Date().toISOString(),
          receivedAt: new Date().toISOString(),
        };

        addMessage(message);
        sendJson(res, 201, { ok: true, message });
      } catch (error) {
        sendJson(res, 400, { error: 'invalid json' });
      }
    });
    return;
  }

  sendJson(res, 404, { error: 'not found' });
}

function serveStatic(req, res, pathname) {
  const filePath = pathname === '/' ? '/index.html' : pathname;
  const resolved = path.normalize(path.join(PUBLIC_DIR, filePath));

  if (!resolved.startsWith(PUBLIC_DIR)) {
    sendText(res, 403, 'Forbidden');
    return;
  }

  fs.readFile(resolved, (err, data) => {
    if (err) {
      sendText(res, 404, 'Not found');
      return;
    }

    const ext = path.extname(resolved);
    const contentType = ext === '.html' ? 'text/html; charset=utf-8' : 'text/plain; charset=utf-8';
    res.writeHead(200, { 'Content-Type': contentType });
    res.end(data);
  });
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const pathname = url.pathname;

  if (pathname === '/events') {
    handleEvents(req, res);
    return;
  }

  if (pathname.startsWith('/api/')) {
    handleApi(req, res, pathname);
    return;
  }

  serveStatic(req, res, pathname);
});

server.listen(PORT, () => {
  console.log(`[BLE Server] running at http://localhost:${PORT}`);
});
