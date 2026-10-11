-- Never recycle key references or nonce claims when content/history is deleted.
CREATE TABLE encryption_keys (
  reference text PRIMARY KEY CHECK (octet_length(reference) BETWEEN 1 AND 256),
  library_id uuid NOT NULL REFERENCES libraries(id),
  enrolled_at timestamptz NOT NULL DEFAULT now(), UNIQUE (library_id, reference)
);
CREATE TABLE nonce_usage (
  key_reference text NOT NULL, nonce bytea NOT NULL CHECK (octet_length(nonce) = 12),
  library_id uuid NOT NULL, envelope_fingerprint bytea NOT NULL CHECK (octet_length(envelope_fingerprint) = 32),
  claimed_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY (key_reference, nonce),
  FOREIGN KEY (library_id, key_reference) REFERENCES encryption_keys(library_id, reference)
);
CREATE TEMP TABLE scriptum_nonce_seed ON COMMIT DROP AS
SELECT key_reference, library_id, source_nonce AS nonce,
  sha256(source_ciphertext || source_digest || convert_to(concat_ws(':','page',library_id::text,space_id::text,id::text,revision::text),'UTF8')) AS fingerprint
FROM pages
UNION ALL SELECT key_reference, library_id, source_nonce,
  sha256(source_ciphertext || source_digest || convert_to(concat_ws(':','page',library_id::text,space_id::text,page_id::text,revision::text),'UTF8'))
FROM page_revisions
UNION ALL SELECT key_reference, library_id, nonce,
  sha256(payload_ciphertext || source_digest || convert_to(concat_ws(':','result',library_id::text,space_id::text,page_id::text,id::text,run_id::text,base_revision::text,kind),'UTF8'))
FROM results;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM scriptum_nonce_seed GROUP BY key_reference HAVING count(DISTINCT library_id) > 1) THEN
    RAISE EXCEPTION 'Legacy key reference spans multiple libraries' USING ERRCODE='23514';
  END IF;
  IF EXISTS (SELECT 1 FROM scriptum_nonce_seed GROUP BY key_reference,nonce HAVING count(DISTINCT fingerprint) > 1) THEN
    RAISE EXCEPTION 'Conflicting historical nonce usage' USING ERRCODE='23505';
  END IF;
END $$;
INSERT INTO encryption_keys(reference,library_id) SELECT DISTINCT key_reference,library_id FROM scriptum_nonce_seed;
INSERT INTO nonce_usage(key_reference,nonce,library_id,envelope_fingerprint) SELECT DISTINCT key_reference,nonce,library_id,fingerprint FROM scriptum_nonce_seed;
ALTER TABLE pages ADD FOREIGN KEY (library_id,key_reference) REFERENCES encryption_keys(library_id,reference);
ALTER TABLE page_revisions ADD FOREIGN KEY (library_id,key_reference) REFERENCES encryption_keys(library_id,reference);
ALTER TABLE results ADD FOREIGN KEY (library_id,key_reference) REFERENCES encryption_keys(library_id,reference);

CREATE FUNCTION reject_nonce_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Nonce/key ownership records are immutable' USING ERRCODE='55000'; END $$;
CREATE TRIGGER immutable_nonce_usage BEFORE UPDATE OR DELETE ON nonce_usage FOR EACH ROW EXECUTE FUNCTION reject_nonce_mutation();
CREATE TRIGGER immutable_key_registry BEFORE UPDATE OR DELETE ON encryption_keys FOR EACH ROW EXECUTE FUNCTION reject_nonce_mutation();

CREATE FUNCTION reserve_envelope_nonce() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE n bytea; fingerprint bytea; previous_fingerprint bytea; claim_count bigint;
BEGIN
  IF TG_TABLE_NAME = 'results' THEN
    IF TG_OP = 'UPDATE' THEN
      IF NEW IS NOT DISTINCT FROM OLD THEN RETURN NEW; END IF;
      RAISE EXCEPTION 'Published encrypted result is immutable' USING ERRCODE='55000';
    END IF;
    n := NEW.nonce;
    fingerprint := sha256(NEW.payload_ciphertext || NEW.source_digest || convert_to(concat_ws(':','result',NEW.library_id::text,NEW.space_id::text,NEW.page_id::text,NEW.id::text,NEW.run_id::text,NEW.base_revision::text,NEW.kind),'UTF8'));
  ELSE
    IF TG_TABLE_NAME = 'pages' THEN
      IF TG_OP = 'UPDATE' THEN
        IF (NEW.library_id,NEW.space_id,NEW.id,NEW.revision,NEW.source_ciphertext,NEW.source_nonce,NEW.source_digest,NEW.key_reference,NEW.envelope_version)
          IS NOT DISTINCT FROM
          (OLD.library_id,OLD.space_id,OLD.id,OLD.revision,OLD.source_ciphertext,OLD.source_nonce,OLD.source_digest,OLD.key_reference,OLD.envelope_version)
        THEN RETURN NEW; END IF;
      END IF;
    END IF;
    n := NEW.source_nonce;
    IF TG_TABLE_NAME = 'pages' THEN
      fingerprint := sha256(NEW.source_ciphertext || NEW.source_digest || convert_to(concat_ws(':','page',NEW.library_id::text,NEW.space_id::text,NEW.id::text,NEW.revision::text),'UTF8'));
    ELSE
      IF TG_OP = 'UPDATE' THEN RAISE EXCEPTION 'Archived envelope is immutable' USING ERRCODE='55000'; END IF;
      fingerprint := sha256(NEW.source_ciphertext || NEW.source_digest || convert_to(concat_ws(':','page',NEW.library_id::text,NEW.space_id::text,NEW.page_id::text,NEW.revision::text),'UTF8'));
    END IF;
  END IF;
  -- Resolve ledger by the actual trigger table's schema, never caller search_path.
  EXECUTE format('INSERT INTO %I.nonce_usage(key_reference,nonce,library_id,envelope_fingerprint) VALUES($1,$2,$3,$4) ON CONFLICT(key_reference,nonce) DO NOTHING',TG_TABLE_SCHEMA)
    USING NEW.key_reference,n,NEW.library_id,fingerprint;
  GET DIAGNOSTICS claim_count = ROW_COUNT;
  IF claim_count = 0 THEN
    EXECUTE format('SELECT envelope_fingerprint FROM %I.nonce_usage WHERE key_reference=$1 AND nonce=$2',TG_TABLE_SCHEMA)
      INTO previous_fingerprint USING NEW.key_reference,n;
    -- A history row may copy the identical previously claimed envelope. It does
    -- not encrypt new bytes and must retain the original revision/target binding.
    IF TG_TABLE_NAME <> 'page_revisions' OR previous_fingerprint IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION 'Nonce already used by an encrypted envelope' USING ERRCODE='23505';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER reserve_page_nonce BEFORE INSERT OR UPDATE ON pages FOR EACH ROW EXECUTE FUNCTION reserve_envelope_nonce();
CREATE TRIGGER reserve_history_nonce BEFORE INSERT OR UPDATE ON page_revisions FOR EACH ROW EXECUTE FUNCTION reserve_envelope_nonce();
CREATE TRIGGER reserve_result_nonce BEFORE INSERT OR UPDATE ON results FOR EACH ROW EXECUTE FUNCTION reserve_envelope_nonce();

-- Exact target linkage, rather than merely existence of any page in a library.
ALTER TABLE schedules ADD UNIQUE (library_id,id,space_id,page_id);
ALTER TABLE runs ADD COLUMN space_id uuid, ADD COLUMN page_id uuid;
UPDATE runs r SET space_id=s.space_id,page_id=s.page_id FROM schedules s WHERE r.library_id=s.library_id AND r.schedule_id=s.id;
ALTER TABLE runs ALTER COLUMN space_id SET NOT NULL, ALTER COLUMN page_id SET NOT NULL;
ALTER TABLE runs ADD FOREIGN KEY (library_id,schedule_id,space_id,page_id) REFERENCES schedules(library_id,id,space_id,page_id);
ALTER TABLE runs ADD UNIQUE (library_id,id,space_id,page_id);
ALTER TABLE results ADD FOREIGN KEY (library_id,run_id,space_id,page_id) REFERENCES runs(library_id,id,space_id,page_id);
