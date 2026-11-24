const { HttpError } = require('../utils/http-error');

// Every field is optional. Keep in sync with lib/features/profile/domain/user_profile.dart.
const TEXT_LIMITS = { name: 80, neighborhood: 80, city: 80, work: 120, education: 120, about: 300 };
const SEXES = ['feminino', 'masculino', 'outro', 'nao_informar'];
const OCCUPATIONS = ['estudante', 'empregado', 'autonomo', 'desempregado', 'aposentado', 'do_lar'];
const FIELDS = [...Object.keys(TEXT_LIMITS), 'birthDate', 'sex', 'occupations'];

function isValidBirthDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime())
    && date.toISOString().slice(0, 10) === value
    && value >= '1900-01-01'
    // One day of slack: the user's timezone may be ahead of UTC.
    && date.getTime() <= Date.now() + 86400000;
}

function validateProfile(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw new HttpError(400, 'Perfil inválido.');
  }
  const unknown = Object.keys(input).find((key) => !FIELDS.includes(key));
  if (unknown) throw new HttpError(400, `Campo desconhecido: ${unknown.slice(0, 40)}`);

  const profile = {};
  for (const [field, limit] of Object.entries(TEXT_LIMITS)) {
    const value = input[field];
    if (value === undefined || value === null) continue;
    if (typeof value !== 'string' || value.trim().length > limit) {
      throw new HttpError(400, `Valor inválido em ${field}.`);
    }
    if (value.trim()) profile[field] = value.trim();
  }
  if (input.birthDate !== undefined && input.birthDate !== null) {
    if (!isValidBirthDate(input.birthDate)) throw new HttpError(400, 'Data de nascimento inválida.');
    profile.birthDate = input.birthDate;
  }
  if (input.sex !== undefined && input.sex !== null) {
    if (!SEXES.includes(input.sex)) throw new HttpError(400, 'Valor inválido em sex.');
    profile.sex = input.sex;
  }
  if (input.occupations !== undefined && input.occupations !== null) {
    if (!Array.isArray(input.occupations) || input.occupations.some((item) => !OCCUPATIONS.includes(item))) {
      throw new HttpError(400, 'Valor inválido em occupations.');
    }
    const selected = OCCUPATIONS.filter((item) => input.occupations.includes(item));
    if (selected.length) profile.occupations = selected;
  }
  return profile;
}

module.exports = { validateProfile };
