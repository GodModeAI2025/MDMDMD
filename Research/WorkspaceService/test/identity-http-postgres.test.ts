import test, { before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID, randomBytes } from "node:crypto";
import { mkdtemp, rm, readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { Pool } from "pg";
import type { PoolClient } from "pg";
import { migrate } from "../src/migrate.ts";
import { WorkspaceStore, sessionDigest } from "../src/workspace-store.ts";
import { IdentityStore } from "../src/identity-store.ts";
import { createGateway, listenGateway } from "../src/http-gateway.ts";
import { schemaIdentifier } from "../src/validation.ts";
import { verificationURL } from "./verification.ts";
import { ownedIssuer } from "./helpers/identity-issuer.ts";

const url = verificationURL(
  process.env.SCRIPTUM_VERIFICATION_DATABASE_URL,
  process.env.SCRIPTUM_ALLOW_VERIFICATION_SCHEMA,
);
const schema = "wsverify_" + randomUUID().replaceAll("-", ""),
  pool = new Pool({
    connectionString: url,
    max: 8,
    application_name: schema,
    connectionTimeoutMillis: 5000,
  }),
  workspace = new WorkspaceStore(pool, schema);
let lock: PoolClient,
  owned = false,
  root: string,
  issuer: Awaited<ReturnType<typeof ownedIssuer>>,
  identity: IdentityStore,
  other: IdentityStore,
  base: string,
  gateway: ReturnType<typeof createGateway>;
let session: {
    sessionToken: string;
    sessionID: string;
    accountID: string;
    expiresAt: string;
    reauthenticationReceipt: string;
  },
  subject = "synthetic-account-" + randomUUID();
before(async () => {
  const version = await pool.query<{ server_version_num: string }>(
    "SHOW server_version_num",
  );
  assert.equal(
    Math.floor(Number(version.rows[0]!.server_version_num) / 10000),
    18,
  );
  lock = await pool.connect();
  await lock.query("SELECT pg_advisory_lock(hashtextextended($1,0))", [
    "scriptum:identity:" + schema,
  ]);
  await pool.query(`CREATE SCHEMA ${schemaIdentifier(schema)}`);
  owned = true;
  await migrate(pool, schema);
  await migrate(pool, schema);
  root = await mkdtemp("/private/tmp/scriptum-identity-http-");
  issuer = await ownedIssuer(join(root, "vault"));
  identity = new IdentityStore(pool, schema, [issuer]);
  other = new IdentityStore(pool, schema, [issuer]);
  gateway = createGateway(workspace, { identity });
  base = await listenGateway(gateway);
});
after(async () => {
  if (gateway) {
    gateway.closeAllConnections();
    await new Promise<void>((resolve) => gateway.close(() => resolve()));
  }
  if (issuer) await issuer.close();
  if (root) await rm(root, { recursive: true, force: true });
  try {
    if (owned)
      await pool.query(`DROP SCHEMA ${schemaIdentifier(schema)} CASCADE`);
  } finally {
    if (lock) {
      await lock.query("SELECT pg_advisory_unlock(hashtextextended($1,0))", [
        "scriptum:identity:" + schema,
      ]);
      lock.release();
    }
    await pool.end();
  }
});
async function http(
  path: string,
  method = "GET",
  token?: string,
  body?: unknown,
) {
  return fetch(base + path, {
    method,
    headers: {
      ...(token ? { authorization: "Bearer " + token } : {}),
      ...(body ? { "content-type": "application/json" } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
}
async function enrollWith(store: IdentityStore, sub: string, origin: string) {
  const challenge = await store.challenge(
      issuer.profile.profileID,
      issuer.profile.consentVersion,
      origin,
    ),
    auth = await issuer.authorize(challenge.nonce, sub);
  return store.enroll(
    {
      challengeID: challenge.challengeID,
      challengeSecret: challenge.challengeSecret,
      state: challenge.state,
      identityToken: auth.identityToken,
      authorizationCode: auth.authorizationCode,
    },
    origin,
  );
}
test("real HTTP challenge -> signed/code/vault session creates no membership and logs no tokens", async () => {
  const created = await http("/identity/challenges", "POST", undefined, {
    profileID: issuer.profile.profileID,
    consentVersion: issuer.profile.consentVersion,
  });
  assert.equal(created.status, 201);
  const challenge = (await created.json()) as Awaited<
    ReturnType<IdentityStore["challenge"]>
  >;
  const auth = await issuer.authorize(challenge.nonce, subject),
    enrolled = await http("/identity/enroll", "POST", undefined, {
      challengeID: challenge.challengeID,
      challengeSecret: challenge.challengeSecret,
      state: challenge.state,
      identityToken: auth.identityToken,
      authorizationCode: auth.authorizationCode,
    });
  assert.equal(enrolled.status, 201);
  session = (await enrolled.json()) as typeof session;
  assert.equal(
    (await http("/session", "GET", session.sessionToken)).status,
    200,
  );
  const tables = await pool.query(
    `SELECT (SELECT count(*) FROM ${schemaIdentifier(schema)}.memberships) AS members,(SELECT count(*) FROM ${schemaIdentifier(schema)}.libraries) AS libraries`,
  );
  assert.equal(Number(tables.rows[0].members), 0);
  assert.equal(Number(tables.rows[0].libraries), 0);
  const rows = await pool.query(
    `SELECT row_to_json(s)::text AS value FROM ${schemaIdentifier(schema)}.server_sessions s`,
  );
  assert.equal(
    rows.rows.some(
      (row) =>
        String(row.value).includes(session.sessionToken) ||
        String(row.value).includes(auth.refreshToken) ||
        String(row.value).includes(auth.identityToken),
    ),
    false,
  );
  const files = await readdir(join(root, "vault"));
  assert.equal(files.length, 1);
  assert.equal(
    (await readFile(join(root, "vault", files[0]!))).includes(
      Buffer.from(auth.refreshToken),
    ),
    false,
  );
  assert.equal(
    (
      await http("/identity/enroll", "POST", undefined, {
        challengeID: challenge.challengeID,
        challengeSecret: challenge.challengeSecret,
        state: challenge.state,
        identityToken: auth.identityToken,
        authorizationCode: auth.authorizationCode,
      })
    ).status,
    401,
  );
});
test("one attempt and shared transactional rate limit across two instances", async () => {
  const challenge = await identity.challenge(
      issuer.profile.profileID,
      issuer.profile.consentVersion,
      "concurrent",
    ),
    auth = await issuer.authorize(challenge.nonce, "concurrent-subject");
  const dto = {
    challengeID: challenge.challengeID,
    challengeSecret: challenge.challengeSecret,
    state: challenge.state,
    identityToken: auth.identityToken,
    authorizationCode: auth.authorizationCode,
  };
  const replies = await Promise.allSettled([
    identity.enroll(dto, "one"),
    other.enroll(dto, "two"),
  ]);
  assert.equal(
    replies.filter((value) => value.status === "fulfilled").length,
    1,
  );
  for (let index = 0; index < 5; index++)
    await (index % 2 ? identity : other).challenge(
      issuer.profile.profileID,
      issuer.profile.consentVersion,
      "shared-origin",
    );
  await assert.rejects(
    other.challenge(
      issuer.profile.profileID,
      issuer.profile.consentVersion,
      "shared-origin",
    ),
  );
});
test("code subject mismatch consumes attempt without account/session publication", async () => {
  const challenge = await identity.challenge(
      issuer.profile.profileID,
      issuer.profile.consentVersion,
      "mismatch",
    ),
    auth = await issuer.authorize(
      challenge.nonce,
      "native-mismatch",
      "exchanged-mismatch",
    );
  const dto = {
    challengeID: challenge.challengeID,
    challengeSecret: challenge.challengeSecret,
    state: challenge.state,
    identityToken: auth.identityToken,
    authorizationCode: auth.authorizationCode,
  };
  await assert.rejects(identity.enroll(dto, "mismatch"));
  await assert.rejects(identity.enroll(dto, "mismatch"));
  const account = await pool.query(
    `SELECT id FROM ${schemaIdentifier(schema)}.accounts WHERE identity_subject=$1`,
    ["native-mismatch"],
  );
  assert.equal(account.rows.length, 0);
  const attempts = await pool.query(
    `SELECT status FROM ${schemaIdentifier(schema)}.identity_challenges WHERE id=$1`,
    [challenge.challengeID],
  );
  assert.equal(attempts.rows[0].status, "failed");
});
test("collision retries preserve existing session and atomic enrolment", async () => {
  let count = 0;
  const fresh = randomBytes(32).toString("base64url");
  const collision = new IdentityStore(pool, schema, [issuer], {
    testSessionToken: () => (++count < 3 ? session.sessionToken : fresh),
  });
  const enrolled = await enrollWith(
    collision,
    "collision-subject",
    "collision",
  );
  assert.equal(count, 3);
  assert.equal(enrolled.sessionToken === fresh, true);
  assert.equal(
    (await identity.session(session.sessionToken)).sessionID,
    session.sessionID,
  );
});
test("signed event without exp deduplicates, email does not grant, disable rejects queued write", async () => {
  const email = await issuer.event(subject, "email-disabled");
  await identity.notification(email);
  await identity.notification(email);
  assert.equal(
    (await identity.session(session.sessionToken)).accountID,
    session.accountID,
  );
  const library = await workspace.createLibrary(
      session.sessionToken,
      "Retained cloud library",
    ),
    space = await workspace.createSpace(session.sessionToken, library, "Space"),
    page = randomUUID(),
    key = "synthetic:" + randomUUID();
  await pool.query(
    `INSERT INTO ${schemaIdentifier(schema)}.encryption_keys(reference,library_id) VALUES($1,$2)`,
    [key, library],
  );
  const envelope = {
    ciphertext: randomBytes(32),
    nonce: randomBytes(12),
    digest: randomBytes(32),
    keyReference: key,
    version: 1 as const,
  };
  const revision = await workspace.createPage(
    session.sessionToken,
    { libraryID: library, spaceID: space, pageID: page },
    envelope,
  );
  const disabling = await pool.connect();
  try {
    await disabling.query("BEGIN");
    await disabling.query(
      `SELECT id FROM ${schemaIdentifier(schema)}.accounts WHERE id=$1 FOR UPDATE`,
      [session.accountID],
    );
    await disabling.query(
      `UPDATE ${schemaIdentifier(schema)}.accounts SET disabled_at=clock_timestamp(),disabled_reason='consent-revoked',auth_epoch=auth_epoch+1 WHERE id=$1`,
      [session.accountID],
    );
    await disabling.query(
      `UPDATE ${schemaIdentifier(schema)}.server_sessions SET revoked_at=clock_timestamp() WHERE account_id=$1`,
      [session.accountID],
    );
    const queued = workspace.writePage(
      session.sessionToken,
      { libraryID: library, spaceID: space, pageID: page },
      revision,
      { ...envelope, nonce: randomBytes(12) },
    );
    let blocked = false;
    for (let attempt = 0; attempt < 100; attempt++) {
      const waiting = await pool.query(
        `SELECT count(*) FROM pg_stat_activity WHERE application_name=$1 AND wait_event_type='Lock' AND query LIKE 'SELECT auth_epoch%'`,
        [schema],
      );
      if (Number(waiting.rows[0].count) > 0) {
        blocked = true;
        break;
      }
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    assert.equal(blocked, true);
    await disabling.query("COMMIT");
    await assert.rejects(queued);
  } finally {
    await disabling.query("ROLLBACK").catch(() => undefined);
    disabling.release();
  }
  const persisted = await pool.query(
    `SELECT revision,source_ciphertext FROM ${schemaIdentifier(schema)}.pages WHERE library_id=$1 AND id=$2`,
    [library, page],
  );
  assert.equal(persisted.rows[0].revision, revision);
  assert.deepEqual(persisted.rows[0].source_ciphertext, envelope.ciphertext);
  const revocation = await issuer.event("collision-subject", "consent-revoked");
  await identity.notification(revocation);
  await identity.notification(revocation);
  const revoked = await pool.query(
    `SELECT disabled_reason FROM ${schemaIdentifier(schema)}.accounts WHERE identity_subject='collision-subject'`,
  );
  assert.equal(revoked.rows[0].disabled_reason, "consent-revoked");
});
test("fresh deletion receipt tombstones but preserves libraries and durably revokes provider", async () => {
  const enrolled = await enrollWith(identity, "deletion-subject", "delete"),
    library = await workspace.createLibrary(
      enrolled.sessionToken,
      "Preserved on delete",
    );
  await identity.deleteAccount(
    enrolled.sessionToken,
    enrolled.reauthenticationReceipt,
    "preserve-owned-libraries",
  );
  await assert.rejects(identity.session(enrolled.sessionToken));
  assert.equal(
    (
      await pool.query(
        `SELECT id FROM ${schemaIdentifier(schema)}.libraries WHERE id=$1`,
        [library],
      )
    ).rows.length,
    1,
  );
  assert.equal(
    (
      await pool.query(
        `SELECT tombstoned_at FROM ${schemaIdentifier(schema)}.accounts WHERE id=$1`,
        [enrolled.accountID],
      )
    ).rows[0].tombstoned_at !== null,
    true,
  );
  const before = issuer.state.revokeRequests;
  await identity.compensate(10);
  assert.equal(issuer.state.revokeRequests > before, true);
  await assert.rejects(
    enrollWith(identity, "deletion-subject", "deleted-retry"),
  );
});

test("same-subject independent challenges converge, session cap and logout-all are atomic", async () => {
  const sub = "session-cap-subject";
  const replies = await Promise.all([
    enrollWith(identity, sub, "cap-first"),
    enrollWith(other, sub, "cap-second"),
  ]);
  assert.equal(replies[0]!.accountID, replies[1]!.accountID);
  for (let index = 0; index < 19; index++)
    await enrollWith(index % 2 ? identity : other, sub, "cap-origin-" + index);
  const active = await pool.query(
    `SELECT count(*) FROM ${schemaIdentifier(schema)}.server_sessions WHERE account_id=$1 AND revoked_at IS NULL AND expires_at>clock_timestamp()`,
    [replies[0]!.accountID],
  );
  assert.equal(Number(active.rows[0].count), 20);
  const originalSessions = await Promise.allSettled(
    replies.map((value) => identity.session(value.sessionToken)),
  );
  assert.equal(
    originalSessions.filter((value) => value.status === "rejected").length,
    1,
  );
  const fresh = await enrollWith(identity, sub, "cap-last");
  const response = await http(
    "/session/logout-all",
    "POST",
    fresh.sessionToken,
  );
  assert.equal(response.status, 204);
  await assert.rejects(identity.session(fresh.sessionToken));
  assert.equal(
    Number(
      (
        await pool.query(
          `SELECT count(*) FROM ${schemaIdentifier(schema)}.server_sessions WHERE account_id=$1 AND revoked_at IS NULL`,
          [fresh.accountID],
        )
      ).rows[0].count,
    ),
    0,
  );
});
test("wrong state consumes one attempt and strict identity wire never admits missing profile/config", async () => {
  const challenge = await identity.challenge(
      issuer.profile.profileID,
      issuer.profile.consentVersion,
      "wrong-state",
    ),
    auth = await issuer.authorize(challenge.nonce, "state-subject");
  const dto = {
    challengeID: challenge.challengeID,
    challengeSecret: challenge.challengeSecret,
    state: randomBytes(32).toString("base64url"),
    identityToken: auth.identityToken,
    authorizationCode: auth.authorizationCode,
  };
  await assert.rejects(identity.enroll(dto, "wrong-state"));
  await assert.rejects(
    identity.enroll({ ...dto, state: challenge.state }, "wrong-state"),
  );
  const row = await pool.query(
    `SELECT status FROM ${schemaIdentifier(schema)}.identity_challenges WHERE id=$1`,
    [challenge.challengeID],
  );
  assert.equal(row.rows[0].status, "failed");
  assert.equal(
    (
      await http("/identity/challenges", "POST", undefined, {
        profileID: issuer.profile.profileID,
        consentVersion: issuer.profile.consentVersion,
        issuer: "https://attacker.invalid",
      })
    ).status,
    400,
  );
  const disabled = createGateway(workspace),
    origin = await listenGateway(disabled);
  try {
    assert.equal(
      (
        await fetch(origin + "/identity/challenges", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: "{}",
        })
      ).status,
      404,
    );
  } finally {
    disabled.closeAllConnections();
    await new Promise<void>((resolve) => disabled.close(() => resolve()));
  }
});
test("vault failure and SQL finalization rollback publish no session but preserve compensating references", async () => {
  const failedVault = {
    mode: "owned-test" as const,
    reference: issuer.vault.reference,
    signClientSecret: issuer.vault.signClientSecret.bind(issuer.vault),
    retain: async () => {
      throw new Error("owned injected vault failure");
    },
    load: issuer.vault.load.bind(issuer.vault),
    remove: issuer.vault.remove.bind(issuer.vault),
  };
  const { OIDCVerifier } = await import("../src/oidc-verifier.ts");
  const cert = await readFile(
    join(process.env.SCRIPTUM_TEST_TLS_DIRECTORY!, "cert.pem"),
  );
  const failing = new IdentityStore(pool, schema, [
    {
      profile: issuer.profile,
      vault: failedVault,
      verifier: new OIDCVerifier(issuer.profile, failedVault, { testCA: cert }),
    },
  ]);
  await assert.rejects(
    enrollWith(failing, "vault-failure-subject", "vault-failure"),
  );
  assert.equal(
    (
      await pool.query(
        `SELECT id FROM ${schemaIdentifier(schema)}.accounts WHERE identity_subject='vault-failure-subject'`,
      )
    ).rows.length,
    0,
  );
  await pool.query(
    `CREATE FUNCTION ${schemaIdentifier(schema)}.fail_identity_session() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.identity_profile_id='owned-profile' THEN RAISE EXCEPTION 'Owned finalization failure'; END IF; RETURN NEW; END $$`,
  );
  await pool.query(
    `CREATE TRIGGER owned_fail_session BEFORE INSERT ON ${schemaIdentifier(schema)}.server_sessions FOR EACH ROW EXECUTE FUNCTION ${schemaIdentifier(schema)}.fail_identity_session()`,
  );
  try {
    await assert.rejects(
      enrollWith(identity, "sql-failure-subject", "sql-failure"),
    );
  } finally {
    await pool.query(
      `DROP TRIGGER owned_fail_session ON ${schemaIdentifier(schema)}.server_sessions`,
    );
    await pool.query(
      `DROP FUNCTION ${schemaIdentifier(schema)}.fail_identity_session()`,
    );
  }
  assert.equal(
    (
      await pool.query(
        `SELECT id FROM ${schemaIdentifier(schema)}.accounts WHERE identity_subject='sql-failure-subject'`,
      )
    ).rows.length,
    0,
  );
  const pending = await pool.query(
    `SELECT vault_reference,state FROM ${schemaIdentifier(schema)}.identity_compensation_jobs WHERE account_id IS NULL AND state='uncertain'`,
  );
  assert.equal(pending.rows.length > 0, true);
  const before = issuer.state.revokeRequests;
  await identity.compensate(32);
  assert.equal(issuer.state.revokeRequests > before, true);
});
test("signed deletion spelling, forged audience and absent notification exp use distinct contracts", async () => {
  const account = await enrollWith(
      identity,
      "signed-delete-subject",
      "signed-delete",
    ),
    bad = await issuer.event("signed-delete-subject", "account-deleted", {
      aud: "wrong-notification-audience",
    });
  await assert.rejects(identity.notification(bad));
  assert.equal(
    (await identity.session(account.sessionToken)).accountID,
    account.accountID,
  );
  const event = await issuer.event("signed-delete-subject", "account-deleted");
  await identity.notification(event);
  await identity.notification(event);
  await assert.rejects(identity.session(account.sessionToken));
  const state = await pool.query(
    `SELECT disabled_reason,tombstoned_at FROM ${schemaIdentifier(schema)}.accounts WHERE id=$1`,
    [account.accountID],
  );
  assert.equal(state.rows[0].disabled_reason, "account-delete");
  assert.equal(state.rows[0].tombstoned_at !== null, true);
  const stale = await issuer.event(subject, "email-enabled", {
    iat: Math.floor(Date.now() / 1000) - 90000,
  });
  await assert.rejects(identity.notification(stale));
});

test("distinct configured issuers never merge equal subjects and cross-issuer events cannot disable", async () => {
  const second = await ownedIssuer(join(root, "other-vault"), {
    profileID: "second-profile",
  });
  try {
    const combined = new IdentityStore(pool, schema, [issuer, second]),
      sub = "equal-subject";
    const a = await enrollWith(combined, sub, "issuer-first");
    const challenge = await combined.challenge(
        second.profile.profileID,
        second.profile.consentVersion,
        "issuer-second",
      ),
      authorization = await second.authorize(challenge.nonce, sub);
    const b = await combined.enroll(
      {
        challengeID: challenge.challengeID,
        challengeSecret: challenge.challengeSecret,
        state: challenge.state,
        identityToken: authorization.identityToken,
        authorizationCode: authorization.authorizationCode,
      },
      "issuer-second",
    );
    assert.notEqual(a.accountID, b.accountID);
    await assert.rejects(
      combined.notification(await second.event(sub, "consent-revoked")),
    );
    assert.equal(
      (await combined.session(a.sessionToken)).accountID,
      a.accountID,
    );
    assert.equal(
      (await combined.session(b.sessionToken)).accountID,
      b.accountID,
    );
  } finally {
    await second.close();
  }
});
test("durable revocation worker drains, never overlaps, and leaves bounded uncertain retries", async () => {
  const enrolled = await enrollWith(identity, "worker-delete", "worker-delete");
  await identity.deleteAccount(
    enrolled.sessionToken,
    enrolled.reauthenticationReceipt,
    "preserve-owned-libraries",
  );
  const { IdentityRevocationWorker } =
    await import("../src/identity-revocation-worker.ts");
  const worker = new IdentityRevocationWorker(identity, {
    intervalMS: 10,
    maximumJobs: 1,
  });
  worker.start();
  try {
    let completed = false;
    for (let attempt = 0; attempt < 200; attempt++) {
      const state = await pool.query(
        `SELECT state FROM ${schemaIdentifier(schema)}.identity_compensation_jobs WHERE account_id=$1`,
        [enrolled.accountID],
      );
      if (state.rows[0].state === "complete") {
        completed = true;
        break;
      }
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    assert.equal(completed, true);
    assert.equal(worker.status.cycles > 0, true);
  } finally {
    await worker.stop();
  }
  const uncertain = await enrollWith(
    identity,
    "uncertain-delete",
    "uncertain-delete",
  );
  await identity.deleteAccount(
    uncertain.sessionToken,
    uncertain.reauthenticationReceipt,
    "preserve-owned-libraries",
  );
  issuer.state.failRevoke = true;
  try {
    for (let attempt = 0; attempt < 4; attempt++) {
      await pool.query(
        `UPDATE ${schemaIdentifier(schema)}.identity_compensation_jobs SET next_attempt_at=clock_timestamp() WHERE account_id=$1`,
        [uncertain.accountID],
      );
      await identity.compensate(32);
    }
    const state = await pool.query(
      `SELECT state,attempts FROM ${schemaIdentifier(schema)}.identity_compensation_jobs WHERE account_id=$1`,
      [uncertain.accountID],
    );
    assert.equal(state.rows[0].state, "uncertain");
    assert.equal(state.rows[0].attempts, 3);
  } finally {
    issuer.state.failRevoke = false;
  }
});

test("global verifier/challenge/rate/event capacities fail closed across instances", async () => {
  const digest = Buffer.alloc(32, 1);
  const ids = (
    await pool.query<{ id: string }>(
      `WITH moment AS MATERIALIZED (SELECT clock_timestamp() AS now) INSERT INTO ${schemaIdentifier(schema)}.identity_challenges(id,secret_digest,nonce_digest,state_digest,profile_id,consent_version,status,attempt_id,created_at,expires_at) SELECT gen_random_uuid(),$1,$1,$1,$2,$3,'verifying',gen_random_uuid(),moment.now,moment.now+interval '5 minutes' FROM moment,generate_series(1,32) RETURNING id`,
      [digest, issuer.profile.profileID, issuer.profile.consentVersion],
    )
  ).rows.map((row) => row.id);
  try {
    const challenge = await identity.challenge(
        issuer.profile.profileID,
        issuer.profile.consentVersion,
        "global-inflight",
      ),
      authorization = await issuer.authorize(
        challenge.nonce,
        "global-inflight",
      );
    await assert.rejects(
      other.enroll(
        {
          challengeID: challenge.challengeID,
          challengeSecret: challenge.challengeSecret,
          state: challenge.state,
          identityToken: authorization.identityToken,
          authorizationCode: authorization.authorizationCode,
        },
        "global-inflight",
      ),
    );
  } finally {
    await pool.query(
      `DELETE FROM ${schemaIdentifier(schema)}.identity_challenges WHERE id=ANY($1::uuid[])`,
      [ids],
    );
  }
  const existing = Number(
    (
      await pool.query(
        `SELECT count(*) FROM ${schemaIdentifier(schema)}.identity_challenges`,
      )
    ).rows[0].count,
  );
  const filled = (
    await pool.query<{ id: string }>(
      `WITH moment AS MATERIALIZED (SELECT clock_timestamp() AS now) INSERT INTO ${schemaIdentifier(schema)}.identity_challenges(id,secret_digest,nonce_digest,state_digest,profile_id,consent_version,status,created_at,expires_at) SELECT gen_random_uuid(),$1,$1,$1,$2,$3,'pending',moment.now,moment.now+interval '5 minutes' FROM moment,generate_series(1,$4) RETURNING id`,
      [
        digest,
        issuer.profile.profileID,
        issuer.profile.consentVersion,
        100000 - existing,
      ],
    )
  ).rows.map((row) => row.id);
  try {
    await assert.rejects(
      identity.challenge(
        issuer.profile.profileID,
        issuer.profile.consentVersion,
        "global-cap",
      ),
    );
    await assert.rejects(
      other.challenge(
        issuer.profile.profileID,
        issuer.profile.consentVersion,
        "global-cap-other",
      ),
    );
  } finally {
    await pool.query(
      `DELETE FROM ${schemaIdentifier(schema)}.identity_challenges WHERE id=ANY($1::uuid[])`,
      [filled],
    );
  }
  const bucketCount = Number(
    (
      await pool.query(
        `SELECT count(*) FROM ${schemaIdentifier(schema)}.identity_rate_buckets`,
      )
    ).rows[0].count,
  );
  await pool.query(
    `WITH moment AS MATERIALIZED (SELECT clock_timestamp() AS now) INSERT INTO ${schemaIdentifier(schema)}.identity_rate_buckets(kind,origin_digest,tokens,updated_at,last_seen_at) SELECT 'challenge',sha256(convert_to('capacity-fixture:'||n::text,'UTF8')),5,moment.now,moment.now FROM moment,generate_series(1,$1) n`,
    [100000 - bucketCount],
  );
  try {
    await assert.rejects(
      other.challenge(
        issuer.profile.profileID,
        issuer.profile.consentVersion,
        "unseen-full-rate",
      ),
    );
  } finally {
    await pool.query(
      `DELETE FROM ${schemaIdentifier(schema)}.identity_rate_buckets WHERE origin_digest IN (SELECT sha256(convert_to('capacity-fixture:'||n::text,'UTF8')) FROM generate_series(1,$1) n)`,
      [100000 - bucketCount],
    );
  }
  const eventCount = Number(
    (
      await pool.query(
        `SELECT count(*) FROM ${schemaIdentifier(schema)}.identity_events`,
      )
    ).rows[0].count,
  );
  await pool.query(
    `WITH moment AS MATERIALIZED (SELECT clock_timestamp() AS now) INSERT INTO ${schemaIdentifier(schema)}.identity_events(token_digest,profile_id,kind,processed_at,expires_at) SELECT sha256(convert_to('event-capacity:'||n::text,'UTF8')),$1,'email-enabled',moment.now,moment.now+interval '25 hours' FROM moment,generate_series(1,$2) n`,
    [issuer.profile.profileID, 100000 - eventCount],
  );
  try {
    await assert.rejects(
      other.notification(await issuer.event("unseen-at-cap", "email-enabled")),
    );
  } finally {
    await pool.query(
      `DELETE FROM ${schemaIdentifier(schema)}.identity_events WHERE token_digest IN (SELECT sha256(convert_to('event-capacity:'||n::text,'UTF8')) FROM generate_series(1,$1) n)`,
      [100000 - eventCount],
    );
  }
});
