const { upsertDevice } = require('../repositories/device-repository');
const { createResponse, getResponseByExternalId } = require('../repositories/response-repository');
const { enqueueJob } = require('../repositories/job-repository');
const { findQuestionIdByPrefix } = require('../repositories/question-repository');
const { createId, normalizeCity, nowIso, toNullableNumber } = require('../utils/helpers');
const { HttpError } = require('../utils/http-error');

async function ingestResponse(payload) {
  const deviceId = String(payload.deviceId || '').trim();
  if (!deviceId) {
    throw new HttpError(400, 'deviceId is required');
  }

  const externalId = String(payload.responseId || payload.externalId || '').trim() || null;
  if (externalId) {
    const existing = await getResponseByExternalId(externalId);
    if (existing) {
      return {
        created: false,
        response: mapResponseRow(existing),
      };
    }
  }

  const answerText = payload.answerText || payload.answer || null;
  // Resolve the full questionId — BLE protocol truncates IDs to 10 chars,
  // so do a prefix lookup to find the real FK value (or null if not found).
  const resolvedQuestionId = await findQuestionIdByPrefix(payload.questionId || null);
  const response = {
    id: createId('rsp'),
    externalId,
    deviceId,
    questionId: resolvedQuestionId,
    answerId: payload.answerId || null,
    answerText: answerText ? String(answerText) : null,
    city: normalizeCity(payload.city),
    latitude: toNullableNumber(payload.latitude),
    longitude: toNullableNumber(payload.longitude),
    status: 'pending',
    rawPayload: payload,
    submittedAt: payload.submittedAt || null,
    receivedAt: nowIso(),
    processedAt: null,
    errorMessage: null,
  };

  await upsertDevice({
    id: deviceId,
    name: payload.deviceName || null,
    city: response.city,
    latitude: response.latitude,
    longitude: response.longitude,
    status: 'active',
  });

  await createResponse(response);
  await enqueueJob({
    jobType: 'process_response',
    entityType: 'response',
    entityId: response.id,
    payload: {
      questionId: response.questionId,
      deviceId: response.deviceId,
    },
  });

  return {
    created: true,
    response,
  };
}

function mapResponseRow(row) {
  return {
    id: row.id,
    externalId: row.external_id,
    deviceId: row.device_id,
    questionId: row.question_id,
    answerId: row.answer_id,
    answerText: row.answer_text,
    city: row.city,
    latitude: row.latitude,
    longitude: row.longitude,
    status: row.status,
    submittedAt: row.submitted_at,
    receivedAt: row.received_at,
    processedAt: row.processed_at,
    errorMessage: row.error_message,
  };
}

module.exports = {
  ingestResponse,
  mapResponseRow,
};
