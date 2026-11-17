const service = require('../services/push-service');

function configuration(req, res) {
  res.set('Cache-Control', 'no-store').json(service.configuration());
}
async function subscribe(req, res) {
  res.json(await service.subscribe(req.body?.token, req.body?.subscription));
}
async function unsubscribe(req, res) {
  await service.unsubscribe(req.body?.token);
  res.json({ subscribed: false });
}
async function test(req, res) {
  res.json(await service.testSubscription(req.body?.token));
}
async function broadcast(req, res) {
  res.json(await service.broadcast(req.body?.title, req.body?.body));
}
async function status(req, res) {
  res.set('Cache-Control', 'no-store').json(await service.status());
}
module.exports = { configuration, subscribe, unsubscribe, test, broadcast, status };
