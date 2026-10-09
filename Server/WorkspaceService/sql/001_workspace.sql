CREATE TABLE IF NOT EXISTS schema_migrations (
  version integer PRIMARY KEY CHECK (version > 0), applied_at timestamptz NOT NULL DEFAULT now(), checksum text NOT NULL CHECK (length(checksum) = 64)
);
CREATE TABLE accounts (
  id uuid PRIMARY KEY, identity_issuer text NOT NULL CHECK (length(identity_issuer) BETWEEN 1 AND 256),
  identity_subject text NOT NULL CHECK (length(identity_subject) BETWEEN 1 AND 256),
  created_at timestamptz NOT NULL DEFAULT now(), UNIQUE (identity_issuer, identity_subject)
);
CREATE TABLE server_sessions (
  id uuid PRIMARY KEY, account_id uuid NOT NULL REFERENCES accounts(id),
  token_digest bytea NOT NULL UNIQUE CHECK (octet_length(token_digest) = 32),
  expires_at timestamptz NOT NULL, revoked_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE libraries (
  id uuid PRIMARY KEY, owner_account_id uuid NOT NULL REFERENCES accounts(id),
  title text NOT NULL CHECK (octet_length(title) BETWEEN 1 AND 4096),
  delegation_ceiling smallint NOT NULL DEFAULT 3 CHECK (delegation_ceiling BETWEEN 0 AND 3), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE spaces (
  library_id uuid NOT NULL REFERENCES libraries(id) ON DELETE CASCADE, id uuid NOT NULL,
  title text NOT NULL CHECK (octet_length(title) BETWEEN 1 AND 4096),
  delegation_ceiling smallint NOT NULL DEFAULT 3 CHECK (delegation_ceiling BETWEEN 0 AND 3),
  PRIMARY KEY (library_id, id)
);
CREATE TABLE pages (
  library_id uuid NOT NULL, space_id uuid NOT NULL, id uuid NOT NULL,
  parent_id uuid, revision uuid NOT NULL, delegation_ceiling smallint NOT NULL DEFAULT 3 CHECK (delegation_ceiling BETWEEN 0 AND 3),
  source_ciphertext bytea NOT NULL CHECK (octet_length(source_ciphertext) BETWEEN 17 AND 2097168),
  source_nonce bytea NOT NULL CHECK (octet_length(source_nonce) = 12), source_digest bytea NOT NULL CHECK (octet_length(source_digest) = 32),
  key_reference text NOT NULL CHECK (octet_length(key_reference) BETWEEN 1 AND 256), envelope_version integer NOT NULL CHECK (envelope_version = 1),
  trashed_at timestamptz, modified_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (library_id, space_id, id), UNIQUE (key_reference, source_nonce),
  FOREIGN KEY (library_id, space_id) REFERENCES spaces(library_id, id) ON DELETE CASCADE,
  FOREIGN KEY (library_id, space_id, parent_id) REFERENCES pages(library_id, space_id, id), CHECK (parent_id IS NULL OR parent_id <> id)
);
CREATE TABLE page_revisions (
  library_id uuid NOT NULL, space_id uuid NOT NULL, page_id uuid NOT NULL, revision uuid NOT NULL,
  source_ciphertext bytea NOT NULL CHECK (octet_length(source_ciphertext) BETWEEN 17 AND 2097168),
  source_nonce bytea NOT NULL CHECK (octet_length(source_nonce) = 12), source_digest bytea NOT NULL CHECK (octet_length(source_digest) = 32),
  key_reference text NOT NULL CHECK (octet_length(key_reference) BETWEEN 1 AND 256), envelope_version integer NOT NULL CHECK (envelope_version = 1),
  captured_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY (library_id, space_id, page_id, revision),
  FOREIGN KEY (library_id, space_id, page_id) REFERENCES pages(library_id, space_id, id)
);
CREATE TABLE memberships (
  id uuid PRIMARY KEY, library_id uuid NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
  account_id uuid NOT NULL REFERENCES accounts(id), resource_kind text NOT NULL CHECK (resource_kind IN ('library','space','page')),
  space_id uuid, page_id uuid, role_rank smallint NOT NULL CHECK (role_rank BETWEEN 0 AND 3),
  CHECK ((resource_kind = 'library' AND space_id IS NULL AND page_id IS NULL) OR (resource_kind = 'space' AND space_id IS NOT NULL AND page_id IS NULL) OR (resource_kind = 'page' AND space_id IS NOT NULL AND page_id IS NOT NULL)),
  FOREIGN KEY (library_id, space_id) REFERENCES spaces(library_id, id) ON DELETE CASCADE,
  FOREIGN KEY (library_id, space_id, page_id) REFERENCES pages(library_id, space_id, id) ON DELETE CASCADE,
  UNIQUE NULLS NOT DISTINCT (library_id, account_id, resource_kind, space_id, page_id)
);
CREATE TABLE schedules (
  library_id uuid NOT NULL, space_id uuid NOT NULL, page_id uuid NOT NULL, id uuid NOT NULL,
  owner_account_id uuid NOT NULL REFERENCES accounts(id), generation bigint NOT NULL CHECK (generation > 0),
  lifecycle text NOT NULL CHECK (lifecycle IN ('draft','awaitingActivation','active','paused','cancelled')),
  rule jsonb NOT NULL CHECK (jsonb_typeof(rule) = 'object' AND octet_length(rule::text) <= 16384),
  PRIMARY KEY (library_id, id), FOREIGN KEY (library_id, space_id, page_id) REFERENCES pages(library_id, space_id, id)
);
CREATE TABLE runs (
  library_id uuid NOT NULL, schedule_id uuid NOT NULL, id uuid NOT NULL, generation bigint NOT NULL CHECK (generation > 0), scheduled_utc timestamptz NOT NULL,
  state text NOT NULL CHECK (state IN ('queued','leased','authorized','reserved','dispatching','running','proposalReady','completed','cancelled','denied','budgetDenied','failed','executionUncertain')),
  lease_fence uuid, lease_expires_at timestamptz, attempts integer NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 3),
  PRIMARY KEY (library_id, id), FOREIGN KEY (library_id, schedule_id) REFERENCES schedules(library_id, id),
  UNIQUE (library_id, schedule_id, generation, scheduled_utc), CHECK ((lease_fence IS NULL) = (lease_expires_at IS NULL))
);
CREATE TABLE reservations (
  library_id uuid NOT NULL, run_id uuid NOT NULL, id uuid NOT NULL, account_id uuid NOT NULL REFERENCES accounts(id),
  currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'), utc_month date NOT NULL CHECK (extract(day from utc_month) = 1),
  held_micros bigint NOT NULL CHECK (held_micros >= 0), actual_micros bigint CHECK (actual_micros BETWEEN 0 AND held_micros),
  state text NOT NULL CHECK (state IN ('held','uncertain','settled','released')), PRIMARY KEY (library_id, id),
  UNIQUE (library_id, run_id), FOREIGN KEY (library_id, run_id) REFERENCES runs(library_id, id), CHECK ((state = 'settled') = (actual_micros IS NOT NULL))
);
CREATE TABLE results (
  library_id uuid NOT NULL, run_id uuid NOT NULL, id uuid NOT NULL, space_id uuid NOT NULL, page_id uuid NOT NULL, base_revision uuid NOT NULL,
  kind text NOT NULL CHECK (kind IN ('proposal','summary')),
  payload_ciphertext bytea NOT NULL CHECK (octet_length(payload_ciphertext) BETWEEN 17 AND 1048592),
  nonce bytea NOT NULL CHECK (octet_length(nonce) = 12), key_reference text NOT NULL CHECK (octet_length(key_reference) BETWEEN 1 AND 256),
  source_digest bytea NOT NULL CHECK (octet_length(source_digest) = 32), created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (library_id, id), UNIQUE (library_id, run_id), UNIQUE (key_reference, nonce),
  FOREIGN KEY (library_id, run_id) REFERENCES runs(library_id, id), FOREIGN KEY (library_id, space_id, page_id) REFERENCES pages(library_id, space_id, id)
);
CREATE TABLE audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, library_id uuid NOT NULL REFERENCES libraries(id), account_id uuid NOT NULL REFERENCES accounts(id),
  event text NOT NULL CHECK (event IN ('library.create','space.create','page.create','page.write','membership.set','membership.revoke')),
  resource_id uuid, recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX memberships_account_library ON memberships(account_id, library_id);
CREATE INDEX server_sessions_account ON server_sessions(account_id);
CREATE INDEX runs_due ON runs(state, scheduled_utc);
