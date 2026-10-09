ALTER TABLE accounts ALTER COLUMN identity_issuer TYPE text COLLATE "C", ALTER COLUMN identity_subject TYPE text COLLATE "C";
ALTER TABLE accounts ADD COLUMN disabled_at timestamptz, ADD COLUMN disabled_reason text,
  ADD COLUMN tombstoned_at timestamptz, ADD COLUMN auth_epoch bigint NOT NULL DEFAULT 0 CHECK(auth_epoch BETWEEN 0 AND 9007199254740991);
ALTER TABLE accounts ADD CHECK(octet_length(identity_issuer) BETWEEN 1 AND 256 AND octet_length(identity_subject) BETWEEN 1 AND 256);
ALTER TABLE accounts ADD CHECK((disabled_at IS NULL) = (disabled_reason IS NULL));
ALTER TABLE accounts ADD CHECK(disabled_reason IS NULL OR disabled_reason IN ('consent-revoked','account-delete','admin-disabled'));
ALTER TABLE accounts ADD CHECK(tombstoned_at IS NULL OR disabled_reason='account-delete');
ALTER TABLE server_sessions ADD COLUMN identity_profile_id text NOT NULL DEFAULT 'legacy-disabled' CHECK(octet_length(identity_profile_id) BETWEEN 1 AND 128),
  ADD COLUMN auth_epoch bigint NOT NULL DEFAULT 0 CHECK(auth_epoch BETWEEN 0 AND 9007199254740991);
UPDATE server_sessions SET revoked_at=COALESCE(revoked_at,clock_timestamp());
CREATE INDEX active_account_sessions ON server_sessions(account_id,created_at) WHERE revoked_at IS NULL;
CREATE TABLE identity_challenges (
 id uuid PRIMARY KEY, secret_digest bytea NOT NULL CHECK(octet_length(secret_digest)=32), nonce_digest bytea NOT NULL CHECK(octet_length(nonce_digest)=32), state_digest bytea NOT NULL CHECK(octet_length(state_digest)=32),
 profile_id text NOT NULL CHECK(octet_length(profile_id) BETWEEN 1 AND 128), consent_version text NOT NULL CHECK(octet_length(consent_version) BETWEEN 1 AND 128),
 status text NOT NULL CHECK(status IN ('pending','verifying','consumed','failed')), attempt_id uuid, created_at timestamptz NOT NULL DEFAULT clock_timestamp(), expires_at timestamptz NOT NULL, consumed_at timestamptz,
 CHECK(expires_at>created_at AND expires_at<=created_at+interval '5 minutes'),
 CHECK((status='pending')=(attempt_id IS NULL)), CHECK((status='consumed')=(consumed_at IS NOT NULL))
);
CREATE INDEX challenge_expiry ON identity_challenges(expires_at);
CREATE TABLE identity_consents (
 account_id uuid NOT NULL REFERENCES accounts(id),profile_id text NOT NULL CHECK(octet_length(profile_id) BETWEEN 1 AND 128),policy_version text NOT NULL CHECK(octet_length(policy_version) BETWEEN 1 AND 128),accepted_at timestamptz NOT NULL DEFAULT clock_timestamp(),PRIMARY KEY(account_id,profile_id,policy_version)
);
CREATE TABLE identity_provider_grants (
 id uuid PRIMARY KEY,account_id uuid NOT NULL REFERENCES accounts(id),profile_id text NOT NULL CHECK(octet_length(profile_id) BETWEEN 1 AND 128),vault_reference text NOT NULL UNIQUE CHECK(octet_length(vault_reference) BETWEEN 1 AND 256),
 state text NOT NULL CHECK(state IN ('retained','revocation-pending','revoked')),created_at timestamptz NOT NULL DEFAULT clock_timestamp(),revoked_at timestamptz,CHECK((state='revoked')=(revoked_at IS NOT NULL))
);
CREATE TABLE identity_events (
 token_digest bytea PRIMARY KEY CHECK(octet_length(token_digest)=32),profile_id text NOT NULL CHECK(octet_length(profile_id) BETWEEN 1 AND 128),jti text CHECK(octet_length(jti) BETWEEN 1 AND 128),
 kind text NOT NULL CHECK(kind IN ('consent-revoked','account-delete','email-enabled','email-disabled')),account_id uuid REFERENCES accounts(id),processed_at timestamptz NOT NULL DEFAULT clock_timestamp(),expires_at timestamptz NOT NULL,
 UNIQUE(profile_id,jti),CHECK(expires_at>=processed_at+interval '25 hours')
);
CREATE TABLE identity_capacity (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),challenge_count integer NOT NULL DEFAULT 0 CHECK(challenge_count BETWEEN 0 AND 100000),inflight_count integer NOT NULL DEFAULT 0 CHECK(inflight_count BETWEEN 0 AND 32),event_count integer NOT NULL DEFAULT 0 CHECK(event_count BETWEEN 0 AND 100000)
);
INSERT INTO identity_capacity(singleton) VALUES(true);
CREATE TABLE identity_rate_buckets (
 kind text NOT NULL CHECK(kind IN ('challenge','enroll')),origin_digest bytea NOT NULL CHECK(octet_length(origin_digest)=32),tokens numeric(12,6) NOT NULL CHECK(tokens BETWEEN 0 AND 10),updated_at timestamptz NOT NULL,last_seen_at timestamptz NOT NULL,PRIMARY KEY(kind,origin_digest)
);
CREATE TABLE identity_compensation_jobs (
 id uuid PRIMARY KEY,challenge_id uuid REFERENCES identity_challenges(id) ON DELETE SET NULL,profile_id text NOT NULL CHECK(octet_length(profile_id) BETWEEN 1 AND 128),vault_reference text NOT NULL UNIQUE CHECK(octet_length(vault_reference) BETWEEN 1 AND 256),
 account_id uuid REFERENCES accounts(id),state text NOT NULL CHECK(state IN ('provisioning','retained','revoke-pending','uncertain','complete')),attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 3),created_at timestamptz NOT NULL DEFAULT clock_timestamp(),next_attempt_at timestamptz NOT NULL DEFAULT clock_timestamp(),lease_id uuid,lease_until timestamptz,
 CHECK((lease_id IS NULL)=(lease_until IS NULL))
);
CREATE TABLE identity_reauthentication (
 receipt_digest bytea PRIMARY KEY CHECK(octet_length(receipt_digest)=32),account_id uuid NOT NULL REFERENCES accounts(id),challenge_id uuid NOT NULL UNIQUE REFERENCES identity_challenges(id),expires_at timestamptz NOT NULL,consumed_at timestamptz
);
CREATE TABLE identity_audit (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,account_id uuid REFERENCES accounts(id),session_id uuid REFERENCES server_sessions(id) ON DELETE SET NULL,
 event text NOT NULL CHECK(event IN ('enrolled','logout-all','disabled','account-delete','provider-revoked','provider-uncertain','challenge-failed','session-cap-revoked')),recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
