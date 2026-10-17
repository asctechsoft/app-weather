-- SW015 — base schema (spec §10.3). Expand-only: later migrations add, never destroy.
-- Uses contrib extensions available in both postgis/postgis and plain PostgreSQL images.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS cube;
CREATE EXTENSION IF NOT EXISTS earthdistance;

-- Dataset imports (GeoNames, VN admin units, timezone data) with audit + rollback pointer.
CREATE TABLE ingestion_runs (
  id            uuid PRIMARY KEY,
  source        text NOT NULL,              -- geonames | vn_admin | ...
  dataset       text NOT NULL,              -- cities500 | cities1000 | allCountries | ...
  url           text,
  checksum_sha256 text,
  license       text,
  started_at    timestamptz NOT NULL DEFAULT now(),
  finished_at   timestamptz,
  status        text NOT NULL DEFAULT 'running' CHECK (status IN ('running','succeeded','failed','rolled_back')),
  is_active     boolean NOT NULL DEFAULT false,
  stats         jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE UNIQUE INDEX ingestion_runs_one_active ON ingestion_runs (source, dataset) WHERE is_active;

CREATE TABLE countries (
  code          char(2) PRIMARY KEY,
  name          text NOT NULL,
  iso3          char(3),
  continent     char(2),
  updated_run_id uuid REFERENCES ingestion_runs(id)
);

-- Administrative units are versioned; GeoNames admin1 codes are not legal codes everywhere.
CREATE TABLE admin_units (
  id              uuid PRIMARY KEY,
  country_code    char(2) NOT NULL,
  level           text NOT NULL,            -- admin1 | admin2 | vn_province | vn_commune
  provider        text NOT NULL,            -- geonames | vn_official
  provider_code   text NOT NULL,
  official_code   text,                     -- only when verified against the source document
  name            text NOT NULL,
  name_ascii      text,
  parent_id       uuid REFERENCES admin_units(id),
  effective_from  date,
  effective_to    date,
  source_document text,
  replaced_by     uuid REFERENCES admin_units(id),
  updated_run_id  uuid REFERENCES ingestion_runs(id),
  UNIQUE (provider, provider_code, effective_from)
);

CREATE TABLE locations (
  location_id       uuid PRIMARY KEY,
  kind              text NOT NULL CHECK (kind IN ('city','administrative_area','gps','place')),
  name              text,
  country_code      char(2),
  admin1_name       text,
  admin2_name       text,
  latitude          double precision NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude         double precision NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  timezone          text NOT NULL,
  coordinate_source text NOT NULL CHECK (coordinate_source IN ('catalog','geocoding','gps')),
  feature_code      text,
  population        bigint,
  in_catalog        boolean NOT NULL DEFAULT false,
  last_requested_at timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  updated_run_id    uuid REFERENCES ingestion_runs(id),
  -- Never hard-deleted while installations/widgets may reference it.
  retired_at        timestamptz
);
-- Bounding-box prefilter (no expression index on ll_to_earth: PG17 builds indexes with a
-- restricted search_path where the earthdistance types are not visible).
CREATE INDEX locations_latlon_idx ON locations (latitude, longitude);
CREATE INDEX locations_country_idx ON locations (country_code);
CREATE INDEX locations_requested_idx ON locations (last_requested_at) WHERE last_requested_at IS NOT NULL;

CREATE TABLE location_external_ids (
  provider     text NOT NULL,
  external_id  text NOT NULL,
  location_id  uuid NOT NULL REFERENCES locations(location_id),
  PRIMARY KEY (provider, external_id)
);
CREATE INDEX location_external_ids_loc_idx ON location_external_ids (location_id);

-- alias_folded = lowercase, diacritics removed (đ→d), computed by the importer.
CREATE TABLE location_aliases (
  location_id   uuid NOT NULL REFERENCES locations(location_id),
  locale        text NOT NULL DEFAULT 'und',
  alias         text NOT NULL,
  alias_folded  text NOT NULL,
  is_preferred  boolean NOT NULL DEFAULT false,
  is_historic   boolean NOT NULL DEFAULT false,
  PRIMARY KEY (location_id, locale, alias_folded)
);
CREATE INDEX location_aliases_trgm_idx ON location_aliases USING gin (alias_folded gin_trgm_ops);
CREATE INDEX location_aliases_prefix_idx ON location_aliases (alias_folded text_pattern_ops);

CREATE TABLE location_admin_links (
  location_id    uuid NOT NULL REFERENCES locations(location_id),
  admin_unit_id  uuid NOT NULL REFERENCES admin_units(id),
  source         text NOT NULL,
  version        text NOT NULL,
  PRIMARY KEY (location_id, admin_unit_id, version)
);

CREATE TABLE weather_snapshots (
  id             bigserial PRIMARY KEY,
  cache_key      text NOT NULL,
  provider_id    text NOT NULL,
  schema_version text NOT NULL,
  fetched_at     timestamptz NOT NULL,
  expires_at     timestamptz NOT NULL,
  retain_until   timestamptz NOT NULL
);
CREATE INDEX weather_snapshots_key_idx ON weather_snapshots (cache_key, fetched_at DESC);

CREATE TABLE provider_capabilities (
  provider     text NOT NULL,
  region       text NOT NULL DEFAULT 'global',
  feature      text NOT NULL,
  entitlement  text NOT NULL,                -- free_dev | commercial | none
  status       text NOT NULL,                -- active | conditional | disabled
  checked_at   timestamptz,
  notes        text,
  PRIMARY KEY (provider, region, feature)
);

-- Installation token is a server-issued bearer credential; only its hash is stored.
CREATE TABLE installations (
  installation_id  uuid PRIMARY KEY,
  token_hash       bytea NOT NULL UNIQUE,
  token_expires_at timestamptz NOT NULL,
  platform         text NOT NULL CHECK (platform IN ('android','ios','web','windows','macos','linux')),
  app_version      text NOT NULL,
  locale           text,
  timezone         text,
  consent          jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at       timestamptz NOT NULL DEFAULT now(),
  last_seen_at     timestamptz NOT NULL DEFAULT now(),
  revoked_at       timestamptz
);

CREATE TABLE push_tokens (
  id               uuid PRIMARY KEY,
  installation_id  uuid NOT NULL REFERENCES installations(installation_id) ON DELETE CASCADE,
  platform         text NOT NULL,
  encrypted_token  bytea NOT NULL,
  token_fingerprint text NOT NULL UNIQUE,
  status           text NOT NULL DEFAULT 'active' CHECK (status IN ('active','invalid','revoked')),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE notification_preferences (
  installation_id  uuid PRIMARY KEY REFERENCES installations(installation_id) ON DELETE CASCADE,
  revision         integer NOT NULL DEFAULT 0,
  config           jsonb NOT NULL,
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE notification_events (
  id               uuid PRIMARY KEY,
  dedupe_key       text NOT NULL UNIQUE,
  installation_id  uuid REFERENCES installations(installation_id) ON DELETE CASCADE,
  type             text NOT NULL,
  scheduled_for    timestamptz NOT NULL,
  sent_at          timestamptz,
  result           text,                    -- accepted | rejected | skipped:<reason> (never "read")
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE alerts (
  alert_id          uuid PRIMARY KEY,
  source_type       text NOT NULL CHECK (source_type IN ('official_alert','app_reminder')),
  provider_id       text NOT NULL,
  issuer            text,
  provider_alert_id text,
  event_code        text NOT NULL,
  severity          text,
  certainty         text,
  urgency           text,
  effective_at      timestamptz,
  expires_at        timestamptz,
  geometry          jsonb,
  area_text         text,
  status            text NOT NULL,           -- active | expired | cancelled | updated
  current_revision  integer NOT NULL DEFAULT 1,
  UNIQUE (provider_id, provider_alert_id)
);

CREATE TABLE alert_revisions (
  alert_id          uuid NOT NULL REFERENCES alerts(alert_id),
  revision          integer NOT NULL,
  original_text     text,
  translated_text   text,
  instruction       text,
  received_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (alert_id, revision)
);

CREATE TABLE feedback (
  ticket_id         text PRIMARY KEY,
  installation_id   uuid REFERENCES installations(installation_id) ON DELETE SET NULL,
  idempotency_key   text NOT NULL,
  content_hash      text NOT NULL,
  type              text NOT NULL CHECK (type IN ('bug','suggestion','other')),
  subject           text NOT NULL,
  message           text NOT NULL,
  email             text,
  diagnostics       jsonb,
  locale            text,
  status            text NOT NULL DEFAULT 'received',
  created_at        timestamptz NOT NULL DEFAULT now(),
  retain_until      timestamptz NOT NULL,
  UNIQUE (installation_id, idempotency_key)
);

CREATE TABLE attachments (
  object_key        text PRIMARY KEY,
  sha256            text,
  owner_installation uuid REFERENCES installations(installation_id) ON DELETE CASCADE,
  ticket_id         text REFERENCES feedback(ticket_id) ON DELETE CASCADE,
  mime              text,
  size_bytes        integer,
  status            text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','scanning','clean','rejected')),
  expires_at        timestamptz NOT NULL
);
