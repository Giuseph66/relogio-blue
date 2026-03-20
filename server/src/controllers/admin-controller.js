const {
  listLocations,
  createLocation,
  updateLocation,
  deleteLocation,
} = require('../repositories/catalog-repository');
const {
  listQuestions,
  createQuestion,
  updateQuestion,
  deleteQuestion,
} = require('../repositories/question-repository');
const { HttpError } = require('../utils/http-error');

async function getLocations(req, res) {
  const locations = await listLocations();
  res.status(200).json({ locations });
}

async function postLocation(req, res) {
  if (!req.body?.name) {
    throw new HttpError(400, 'name is required');
  }
  const location = await createLocation(req.body);
  res.status(201).json({ ok: true, location });
}

async function putLocation(req, res) {
  const location = await updateLocation(req.params.locationId, req.body || {});
  if (!location) {
    throw new HttpError(404, 'location not found');
  }
  res.status(200).json({ ok: true, location });
}

async function removeLocation(req, res) {
  const deleted = await deleteLocation(req.params.locationId);
  if (!deleted) {
    throw new HttpError(404, 'location not found');
  }
  res.status(200).json({ ok: true });
}

async function getQuestions(req, res) {
  const questions = await listQuestions();
  res.status(200).json({ questions });
}

async function postQuestion(req, res) {
  if (!req.body?.prompt) {
    throw new HttpError(400, 'prompt is required');
  }
  const question = await createQuestion(req.body);
  res.status(201).json({ ok: true, question });
}

async function putQuestion(req, res) {
  const question = await updateQuestion(req.params.questionId, req.body || {});
  if (!question) {
    throw new HttpError(404, 'question not found');
  }
  res.status(200).json({ ok: true, question });
}

async function removeQuestion(req, res) {
  const deleted = await deleteQuestion(req.params.questionId);
  if (!deleted) {
    throw new HttpError(404, 'question not found');
  }
  res.status(200).json({ ok: true });
}

async function getCatalog(req, res) {
  const [locations, questions] = await Promise.all([
    listLocations(),
    listQuestions(),
  ]);
  res.status(200).json({ locations, questions });
}

module.exports = {
  getCatalog,
  getLocations,
  postLocation,
  putLocation,
  removeLocation,
  getQuestions,
  postQuestion,
  putQuestion,
  removeQuestion,
};
