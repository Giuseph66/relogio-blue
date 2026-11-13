const {
  getPublicSummary,
  listPublicLocations,
  listQuestionResults,
  listRecentPublicResponses,
  listPublicVolumeByDay,
  listPublicTopCities,
  listAllPublicResponses,
} = require('../repositories/public-stats-repository');
const { HttpError } = require('../utils/http-error');

/*
 * Public (unauthenticated) endpoints: aggregated, anonymised data only — no device
 * identifiers, response coordinates or internal processing details.
 */

// `tz` = browser's Date#getTimezoneOffset() (minutes, UTC-4 => 240), so "today" matches local time.
function tzModifierFrom(query) {
  const tz = Math.max(-840, Math.min(840, Math.trunc(Number(query.tz) || 0)));
  return `${tz > 0 ? '-' : '+'}${Math.abs(tz)} minutes`;
}

async function getPublicDashboard(req, res) {
  const tzModifier = tzModifierFrom(req.query);

  const [summary, locations, questions, recentResponses, volumeByDay, topCities] = await Promise.all([
    getPublicSummary(tzModifier),
    listPublicLocations(),
    listQuestionResults(),
    listRecentPublicResponses(20),
    listPublicVolumeByDay(14, tzModifier),
    listPublicTopCities(6),
  ]);

  res.set('Cache-Control', 'no-store');
  res.status(200).json({
    generatedAt: new Date().toISOString(),
    summary,
    locations,
    questions,
    recentResponses,
    volumeByDay,
    topCities,
  });
}

/* ---------------- Open data export ---------------- */

const DATASETS = {
  respostas: {
    columns: ['data_hora_utc', 'local', 'cidade', 'pergunta', 'resposta'],
    async rows() {
      const items = await listAllPublicResponses();
      return items.map((r) => [r.receivedAt, r.locationName, r.city, r.questionPrompt, r.answer]);
    },
  },
  resultados: {
    columns: ['pergunta', 'local', 'cidade', 'opcao', 'total', 'percentual'],
    async rows() {
      const questions = await listQuestionResults();
      return questions.flatMap((q) =>
        q.options.map((o) => [
          q.prompt,
          q.locationName,
          q.city,
          o.label,
          o.total,
          q.total ? Math.round((o.total / q.total) * 1000) / 10 : 0,
        ]),
      );
    },
  },
  'por-dia': {
    columns: ['data', 'total'],
    async rows(req) {
      const items = await listPublicVolumeByDay(365, tzModifierFrom(req.query));
      return items.map((d) => [d.day, d.total]);
    },
  },
  locais: {
    columns: ['local', 'cidade', 'latitude', 'longitude', 'raio_m', 'total_respostas'],
    async rows() {
      const items = await listPublicLocations();
      return items.map((l) => [l.name, l.city, l.latitude, l.longitude, l.radiusMeters, l.responses]);
    },
  },
};

function csvCell(value) {
  if (value === null || value === undefined) return '';
  // pt-BR CSV convention: `;` separator and decimal comma.
  if (typeof value === 'number') return String(value).replace('.', ',');
  const text = String(value);
  return /[";\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

async function exportPublicDataset(req, res) {
  const match = /^([a-z-]+)\.(csv|json)$/.exec(String(req.params.file || ''));
  const dataset = match && DATASETS[match[1]];
  if (!dataset) {
    throw new HttpError(404, 'dataset not found');
  }

  const [, name, format] = match;
  const rows = await dataset.rows(req);
  const stamp = new Date().toISOString().slice(0, 10);

  res.set('Cache-Control', 'public, max-age=60');
  res.set('Content-Disposition', `attachment; filename="geonexo-${name}-${stamp}.${format}"`);

  if (format === 'json') {
    const data = rows.map((row) => Object.fromEntries(dataset.columns.map((col, i) => [col, row[i] ?? null])));
    res.type('application/json').send(JSON.stringify({ dataset: name, generatedAt: new Date().toISOString(), total: data.length, data }, null, 2));
    return;
  }

  // `;` separator + UTF-8 BOM: opens correctly in Excel pt-BR and still parses in any CSV tool.
  const lines = [dataset.columns, ...rows].map((row) => row.map(csvCell).join(';'));
  res.type('text/csv; charset=utf-8').send(`﻿${lines.join('\r\n')}\r\n`);
}

module.exports = {
  getPublicDashboard,
  exportPublicDataset,
};
