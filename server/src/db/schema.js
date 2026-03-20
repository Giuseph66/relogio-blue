const schema = `
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  name TEXT,
  last_city TEXT,
  last_latitude REAL,
  last_longitude REAL,
  last_seen_at TEXT,
  last_sync_at TEXT,
  status TEXT NOT NULL DEFAULT 'new',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS message_events (
  id TEXT PRIMARY KEY,
  content TEXT NOT NULL,
  device_id TEXT,
  device_name TEXT,
  source TEXT NOT NULL DEFAULT 'relay',
  timestamp TEXT NOT NULL,
  received_at TEXT NOT NULL,
  metadata_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS locations (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  city TEXT,
  latitude REAL,
  longitude REAL,
  radius_meters REAL NOT NULL DEFAULT 100,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS location_rules (
  id TEXT PRIMARY KEY,
  location_id TEXT NOT NULL,
  rule_type TEXT NOT NULL,
  rule_value TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 100,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS questions (
  id TEXT PRIMARY KEY,
  prompt TEXT NOT NULL,
  location_id TEXT,
  city TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  reactive_enabled INTEGER NOT NULL DEFAULT 1,
  valid_from TEXT,
  valid_until TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS question_options (
  id TEXT PRIMARY KEY,
  question_id TEXT NOT NULL,
  option_id TEXT NOT NULL,
  label TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS responses (
  id TEXT PRIMARY KEY,
  external_id TEXT UNIQUE,
  device_id TEXT NOT NULL,
  question_id TEXT,
  answer_id TEXT,
  answer_text TEXT,
  city TEXT,
  latitude REAL,
  longitude REAL,
  status TEXT NOT NULL DEFAULT 'pending',
  raw_payload_json TEXT NOT NULL,
  submitted_at TEXT,
  received_at TEXT NOT NULL,
  processed_at TEXT,
  error_message TEXT,
  FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE,
  FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS jobs (
  id TEXT PRIMARY KEY,
  job_type TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  attempts INTEGER NOT NULL DEFAULT 0,
  available_at TEXT NOT NULL,
  started_at TEXT,
  finished_at TEXT,
  error_message TEXT,
  payload_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_message_events_received_at
  ON message_events(received_at DESC);

CREATE INDEX IF NOT EXISTS idx_locations_city
  ON locations(city);

CREATE INDEX IF NOT EXISTS idx_location_rules_location
  ON location_rules(location_id, is_active, priority);

CREATE INDEX IF NOT EXISTS idx_questions_status
  ON questions(status, reactive_enabled);

CREATE INDEX IF NOT EXISTS idx_question_options_question
  ON question_options(question_id, sort_order);

CREATE INDEX IF NOT EXISTS idx_responses_device_status
  ON responses(device_id, status, received_at DESC);

CREATE INDEX IF NOT EXISTS idx_jobs_status_available
  ON jobs(status, available_at, job_type);
`;

module.exports = { schema };
