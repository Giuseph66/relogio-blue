const crypto = require('crypto');
const { upsertDevice } = require('../repositories/device-repository');
const { createResponse, getResponseByExternalId, getClaimSecret } = require('../repositories/response-repository');
const { enqueueJob } = require('../repositories/job-repository');
const { findQuestionIdByPrefix } = require('../repositories/question-repository');
const { createId, normalizeCity, nowIso, toNullableNumber } = require('../utils/helpers');
const { HttpError } = require('../utils/http-error');
const { broadcastEvent } = require('./sse-service');

// Per question, so stored keys cannot link the answers of one device together.
async function claimKeyFor(deviceKey, questionId) {
  return crypto.createHmac('sha256', await getClaimSecret())
    .update(`${deviceKey}\n${questionId}`).digest('hex');
}

/**
 * `deviceKey` identifies the phone/browser and is never stored; `deviceId` is
 * the generic label kept with the answer. Administrators may answer repeatedly.
 */
async function ingestResponse(payload, { admin, deviceKey, deviceId }) {

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
  if (!admin && !resolvedQuestionId) {
    throw new HttpError(410, 'Esta pergunta não está mais disponível.');
  }
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
    rawPayload: { ...payload, deviceId },
    claimKey: admin ? null : await claimKeyFor(deviceKey, resolvedQuestionId),
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

  if (!await createResponse(response)) {
    // Same answer sent twice at once, or a second answer to the question.
    const existing = externalId && await getResponseByExternalId(externalId);
    if (existing) return { created: false, response: mapResponseRow(existing) };
    throw new HttpError(409, 'Este dispositivo já respondeu a esta pergunta.');
  }
  await enqueueJob({
    jobType: 'process_response',
    entityType: 'response',
    entityId: response.id,
    payload: {
      questionId: response.questionId,
      deviceId: response.deviceId,
    },
  });

  // Only a signal: dashboards refetch their own (scoped) data.
  broadcastEvent('response', { id: response.id, receivedAt: response.receivedAt });

  const { claimKey, ...stored } = response;
  return {
    created: true,
    response: stored,
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
