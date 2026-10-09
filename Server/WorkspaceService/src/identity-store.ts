import {
  createHash,
  randomBytes,
  randomUUID,
  timingSafeEqual,
} from "node:crypto";
import type { Pool, PoolClient } from "pg";
import { transaction } from "./transaction.ts";
import { sessionDigest } from "./workspace-store.ts";
import { IdentityError } from "./identity-config.ts";
import type { IdentityProfile } from "./identity-config.ts";
import {
  OIDCVerifier,
  assertVerifiedIdentity,
  assertVerifiedEvent,
} from "./oidc-verifier.ts";
import type {
  ChallengeProofContext,
  VerifiedIdentity,
  VerifiedIdentityEvent,
} from "./oidc-verifier.ts";
import type { IdentityVault } from "./identity-vault.ts";

export interface IdentityComponents {
  profile: IdentityProfile;
  verifier: OIDCVerifier;
  vault: IdentityVault;
}
export interface EnrollmentDTO {
  challengeID: string;
  challengeSecret: string;
  state: string;
  identityToken: string;
  authorizationCode: string;
}
interface ChallengeRow {
  id: string;
  profile_id: string;
  consent_version: string;
  nonce_digest: Buffer;
  state_digest: Buffer;
  created_at: Date;
  expires_at: Date;
  attempt_id: string;
}
export class IdentityStore {
  readonly #pool: Pool;
  readonly #schema: string;
  readonly #profiles: ReadonlyMap<string, IdentityComponents>;
  readonly #sessionToken: () => string;
  constructor(
    pool: Pool,
    schema: string,
    components: readonly IdentityComponents[],
    options: { testSessionToken?: () => string } = {},
  ) {
    if (
      !components.length ||
      components.length > 8 ||
      new Set(components.map((value) => value.profile.profileID)).size !==
        components.length
    )
      throw new IdentityError("unavailable");
    if (
      options.testSessionToken &&
      components.some((value) => value.profile.mode !== "owned-test")
    )
      throw new IdentityError("unavailable");
    this.#sessionToken =
      options.testSessionToken ?? (() => randomBytes(32).toString("base64url"));
    this.#pool = pool;
    this.#schema = schema;
    this.#profiles = new Map(
      components.map((value) => {
        if (
          value.verifier.profile !== value.profile ||
          value.vault.reference !== value.profile.grantVaultReference ||
          ["signClientSecret", "retain", "load", "remove"].some(
            (name) =>
              typeof (value.vault as unknown as Record<string, unknown>)[
                name
              ] !== "function",
          )
        )
          throw new IdentityError("unavailable");
        return [value.profile.profileID, Object.freeze({ ...value })];
      }),
    );
  }
  #component(profileID: string): IdentityComponents {
    const value = this.#profiles.get(profileID);
    if (!value) throw new IdentityError("unavailable");
    return value;
  }
  async #capacity(client: PoolClient): Promise<void> {
    await client.query(
      "SELECT singleton FROM identity_capacity WHERE singleton=true FOR UPDATE",
    );
    await client.query(
      "DELETE FROM identity_reauthentication WHERE expires_at<clock_timestamp()",
    );
    await client.query(
      "DELETE FROM identity_challenges WHERE expires_at<clock_timestamp()-interval '24 hours'",
    );
    await client.query(
      "DELETE FROM identity_events WHERE expires_at<clock_timestamp()",
    );
    await client.query(
      "DELETE FROM identity_rate_buckets WHERE last_seen_at<clock_timestamp()-interval '15 minutes'",
    );
    await client.query(
      "DELETE FROM identity_compensation_jobs WHERE state='complete' AND next_attempt_at<clock_timestamp()-interval '30 days'",
    );
    await client.query(
      "DELETE FROM identity_provider_grants WHERE state='revoked' AND revoked_at<clock_timestamp()-interval '30 days'",
    );
    await client.query(
      "DELETE FROM server_sessions WHERE revoked_at<clock_timestamp()-interval '30 days' OR expires_at<clock_timestamp()-interval '30 days'",
    );
    await client.query(
      "UPDATE identity_capacity SET challenge_count=(SELECT count(*) FROM identity_challenges),inflight_count=(SELECT count(*) FROM identity_challenges WHERE status=$1 AND expires_at>clock_timestamp()),event_count=(SELECT count(*) FROM identity_events) WHERE singleton=true",
      ["verifying"],
    );
  }
  async #rate(
    client: PoolClient,
    kind: "challenge" | "enroll",
    origin: string,
  ): Promise<void> {
    if (!origin || Buffer.byteLength(origin) > 128)
      throw new IdentityError("invalid");
    const hash = createHash("sha256").update(origin).digest(),
      capacity = kind === "challenge" ? 5 : 10;
    const now = (
      await client.query<{ now: Date }>("SELECT clock_timestamp() AS now")
    ).rows[0]!.now;
    const existing = await client.query<{ tokens: string; updated_at: Date }>(
      "SELECT tokens,updated_at FROM identity_rate_buckets WHERE kind=$1 AND origin_digest=$2",
      [kind, hash],
    );
    const row = existing.rows[0];
    if (!row) {
      const count = await client.query<{ count: string }>(
        "SELECT count(*) FROM identity_rate_buckets",
      );
      if (Number(count.rows[0]!.count) >= 100000)
        throw new IdentityError("limited");
      await client.query(
        "INSERT INTO identity_rate_buckets(kind,origin_digest,tokens,updated_at,last_seen_at) VALUES($1,$2,$3,$4,$4)",
        [kind, hash, capacity - 1, now],
      );
      return;
    }
    const tokens = Math.min(
      capacity,
      Number(row.tokens) +
        (Math.max(0, (now.getTime() - row.updated_at.getTime()) / 1000) *
          capacity) /
          60,
    );
    if (tokens < 1) throw new IdentityError("limited");
    await client.query(
      "UPDATE identity_rate_buckets SET tokens=$3,updated_at=$4,last_seen_at=$4 WHERE kind=$1 AND origin_digest=$2",
      [kind, hash, tokens - 1, now],
    );
  }
  async challenge(
    profileID: string,
    consentVersion: string,
    origin: string,
  ): Promise<{
    challengeID: string;
    challengeSecret: string;
    nonce: string;
    state: string;
    expiresAt: string;
  }> {
    const component = this.#component(profileID);
    if (consentVersion !== component.profile.consentVersion)
      throw new IdentityError("invalid");
    const id = randomUUID(),
      secret = randomBytes(32).toString("base64url"),
      nonce = randomBytes(32).toString("base64url"),
      state = randomBytes(32).toString("base64url");
    const expires = await transaction(
      this.#pool,
      this.#schema,
      async (client) => {
        await this.#capacity(client);
        await this.#rate(client, "challenge", origin);
        const count = await client.query<{ count: string }>(
          "SELECT count(*) FROM identity_challenges",
        );
        if (Number(count.rows[0]!.count) >= 100000)
          throw new IdentityError("limited");
        const result = await client.query<{ expires_at: Date }>(
          "WITH moment AS MATERIALIZED (SELECT clock_timestamp() AS now) INSERT INTO identity_challenges(id,secret_digest,nonce_digest,state_digest,profile_id,consent_version,status,created_at,expires_at) SELECT $1,$2,$3,$4,$5,$6,'pending',moment.now,moment.now+interval '5 minutes' FROM moment RETURNING expires_at",
          [
            id,
            sessionDigest(secret),
            sessionDigest(nonce),
            sessionDigest(state),
            profileID,
            consentVersion,
          ],
        );
        await client.query(
          "UPDATE identity_capacity SET challenge_count=(SELECT count(*) FROM identity_challenges),inflight_count=(SELECT count(*) FROM identity_challenges WHERE status=$1 AND expires_at>clock_timestamp()) WHERE singleton=true",
          ["verifying"],
        );
        return result.rows[0]!.expires_at;
      },
    );
    return {
      challengeID: id,
      challengeSecret: secret,
      nonce,
      state,
      expiresAt: expires.toISOString(),
    };
  }
  async #claim(dto: EnrollmentDTO, origin: string): Promise<ChallengeRow> {
    if (
      !/^[0-9a-f-]{36}$/i.test(dto.challengeID) ||
      ![dto.challengeSecret, dto.state].every((value) =>
        /^[A-Za-z0-9_-]{43}$/.test(value),
      )
    )
      throw new IdentityError("invalid");
    const claimed = await transaction(
      this.#pool,
      this.#schema,
      async (client) => {
        await this.#capacity(client);
        await this.#rate(client, "enroll", origin);
        const inflight = await client.query<{ count: string }>(
          "SELECT count(*) FROM identity_challenges WHERE status='verifying' AND expires_at>clock_timestamp()",
        );
        if (Number(inflight.rows[0]!.count) >= 32)
          throw new IdentityError("limited");
        const result = await client.query<ChallengeRow>(
          "UPDATE identity_challenges SET status='verifying',attempt_id=$3 WHERE id=$1 AND secret_digest=$2 AND status='pending' AND expires_at>clock_timestamp() RETURNING *",
          [dto.challengeID, sessionDigest(dto.challengeSecret), randomUUID()],
        );
        const row = result.rows[0];
        if (!row) return undefined;
        if (!timingSafeEqual(row.state_digest, sessionDigest(dto.state))) {
          await client.query(
            "UPDATE identity_challenges SET status='failed' WHERE id=$1 AND attempt_id=$2",
            [row.id, row.attempt_id],
          );
          await client.query(
            "INSERT INTO identity_audit(event) VALUES('challenge-failed')",
          );
          return undefined;
        }
        await client.query(
          "UPDATE identity_capacity SET inflight_count=(SELECT count(*) FROM identity_challenges WHERE status=$1 AND expires_at>clock_timestamp()) WHERE singleton=true",
          ["verifying"],
        );
        return row;
      },
    );
    if (!claimed) throw new IdentityError("unauthenticated");
    return claimed;
  }
  async enroll(
    dto: EnrollmentDTO,
    origin: string,
  ): Promise<{
    sessionToken: string;
    sessionID: string;
    accountID: string;
    expiresAt: string;
    reauthenticationReceipt: string;
  }> {
    const challenge = await this.#claim(dto, origin),
      component = this.#component(challenge.profile_id),
      jobID = randomUUID(),
      reference = "grant:" + randomUUID();
    const context: ChallengeProofContext = {
      challengeID: challenge.id,
      attemptID: challenge.attempt_id,
      nonceDigest: Buffer.from(challenge.nonce_digest),
      createdAt: challenge.created_at,
      expiresAt: challenge.expires_at,
    };
    const controller = new AbortController(),
      deadline = setTimeout(() => controller.abort(), 10000);
    try {
      // Durable opaque compensation reference precedes every issuer/vault call.
      await transaction(this.#pool, this.#schema, async (client) => {
        await this.#capacity(client);
        const count = await client.query<{ count: string }>(
          "SELECT count(*) FROM identity_compensation_jobs",
        );
        if (Number(count.rows[0]!.count) >= 100000)
          throw new IdentityError("limited");
        await client.query(
          "INSERT INTO identity_compensation_jobs(id,challenge_id,profile_id,vault_reference,state) VALUES($1,$2,$3,$4,'provisioning')",
          [jobID, challenge.id, challenge.profile_id, reference],
        );
      });
      const proof = await component.verifier.verifyAndRedeem(
        context,
        dto.identityToken,
        dto.authorizationCode,
        controller.signal,
      );
      assertVerifiedIdentity(proof);
      await component.vault.retain(
        reference,
        {
          profileID: proof.profileID,
          identityDigest: proof.identityDigest,
          refreshToken: proof.refreshToken,
        },
        controller.signal,
      );
      if (controller.signal.aborted) throw new IdentityError("unavailable");
      return await this.#finalize(challenge, proof, reference, jobID);
    } catch (error) {
      await transaction(this.#pool, this.#schema, async (client) => {
        await this.#capacity(client);
        await client.query(
          "UPDATE identity_challenges SET status='failed' WHERE id=$1 AND attempt_id=$2 AND status='verifying'",
          [challenge.id, challenge.attempt_id],
        );
        await client.query(
          "UPDATE identity_compensation_jobs SET state='uncertain' WHERE id=$1 AND state='provisioning'",
          [jobID],
        );
        await client.query(
          "UPDATE identity_capacity SET inflight_count=(SELECT count(*) FROM identity_challenges WHERE status=$1 AND expires_at>clock_timestamp()) WHERE singleton=true",
          ["verifying"],
        );
        await client.query(
          "INSERT INTO identity_audit(event) VALUES('challenge-failed')",
        );
      }).catch(() => undefined);
      throw error instanceof IdentityError
        ? error
        : new IdentityError("unavailable");
    } finally {
      clearTimeout(deadline);
    }
  }
  async #finalize(
    challenge: ChallengeRow,
    proof: VerifiedIdentity,
    reference: string,
    jobID: string,
  ) {
    assertVerifiedIdentity(proof);
    if (
      proof.challengeID !== challenge.id ||
      proof.attemptID !== challenge.attempt_id
    )
      throw new IdentityError("unauthenticated");
    return transaction(this.#pool, this.#schema, async (client) => {
      await this.#capacity(client);
      const valid = await client.query(
        "SELECT id FROM identity_challenges WHERE id=$1 AND attempt_id=$2 AND status='verifying' AND expires_at>clock_timestamp() FOR UPDATE",
        [challenge.id, challenge.attempt_id],
      );
      if (!valid.rows[0]) throw new IdentityError("unauthenticated");
      await client.query(
        "INSERT INTO accounts(id,identity_issuer,identity_subject) VALUES($1,$2,$3) ON CONFLICT(identity_issuer,identity_subject) DO NOTHING",
        [randomUUID(), proof.issuer, proof.subject],
      );
      const account = await client.query<{
        id: string;
        auth_epoch: string;
        disabled_at: Date | null;
        tombstoned_at: Date | null;
      }>(
        "SELECT id,auth_epoch,disabled_at,tombstoned_at FROM accounts WHERE identity_issuer=$1 AND identity_subject=$2 FOR UPDATE",
        [proof.issuer, proof.subject],
      );
      const row = account.rows[0];
      if (!row || row.disabled_at || row.tombstoned_at)
        throw new IdentityError("deleted");
      const live = await client.query<{ id: string }>(
        "SELECT id FROM server_sessions WHERE account_id=$1 AND revoked_at IS NULL AND expires_at>clock_timestamp() ORDER BY created_at,id FOR UPDATE",
        [row.id],
      );
      for (const session of live.rows.slice(
        0,
        Math.max(0, live.rows.length - 19),
      )) {
        await client.query(
          "UPDATE server_sessions SET revoked_at=clock_timestamp() WHERE id=$1",
          [session.id],
        );
        await client.query(
          "INSERT INTO identity_audit(account_id,session_id,event) VALUES($1,$2,'session-cap-revoked')",
          [row.id, session.id],
        );
      }
      const sessionID = randomUUID();
      let token = "",
        expiresAt: Date | undefined;
      for (let attempt = 0; attempt < 3; attempt++) {
        token = this.#sessionToken();
        const session = await client.query<{ expires_at: Date }>(
          "WITH moment AS MATERIALIZED (SELECT clock_timestamp() AS now) INSERT INTO server_sessions(id,account_id,token_digest,created_at,expires_at,identity_profile_id,auth_epoch) SELECT $1,$2,$3,moment.now,moment.now+interval '8 hours',$4,$5 FROM moment ON CONFLICT(token_digest) DO NOTHING RETURNING expires_at",
          [
            sessionID,
            row.id,
            sessionDigest(token),
            proof.profileID,
            row.auth_epoch,
          ],
        );
        if (session.rows[0]) {
          expiresAt = session.rows[0].expires_at;
          break;
        }
      }
      if (!expiresAt) throw new IdentityError("unavailable");
      await client.query(
        "INSERT INTO identity_consents(account_id,profile_id,policy_version) VALUES($1,$2,$3) ON CONFLICT DO NOTHING",
        [row.id, proof.profileID, challenge.consent_version],
      );
      await client.query(
        "INSERT INTO identity_provider_grants(id,account_id,profile_id,vault_reference,state) VALUES($1,$2,$3,$4,'retained')",
        [randomUUID(), row.id, proof.profileID, reference],
      );
      await client.query(
        "UPDATE identity_compensation_jobs SET state='retained',account_id=$2 WHERE id=$1",
        [jobID, row.id],
      );
      await client.query(
        "UPDATE identity_challenges SET status='consumed',consumed_at=clock_timestamp() WHERE id=$1 AND attempt_id=$2",
        [challenge.id, challenge.attempt_id],
      );
      const receipt = randomBytes(32).toString("base64url");
      await client.query(
        "INSERT INTO identity_reauthentication(receipt_digest,account_id,challenge_id,expires_at) VALUES($1,$2,$3,clock_timestamp()+interval '5 minutes')",
        [sessionDigest(receipt), row.id, challenge.id],
      );
      await client.query(
        "UPDATE identity_capacity SET inflight_count=(SELECT count(*) FROM identity_challenges WHERE status=$1 AND expires_at>clock_timestamp()) WHERE singleton=true",
        ["verifying"],
      );
      await client.query(
        "INSERT INTO identity_audit(account_id,session_id,event) VALUES($1,$2,'enrolled')",
        [row.id, sessionID],
      );
      return {
        sessionToken: token,
        sessionID,
        accountID: row.id,
        expiresAt: expiresAt.toISOString(),
        reauthenticationReceipt: receipt,
      };
    });
  }
  async session(
    token: string,
  ): Promise<{ accountID: string; sessionID: string; expiresAt: string }> {
    return transaction(this.#pool, this.#schema, async (client) => {
      const current = await this.#session(client, token, false);
      return {
        accountID: current.accountID,
        sessionID: current.sessionID,
        expiresAt: current.expiresAt.toISOString(),
      };
    });
  }
  async #session(
    client: PoolClient,
    token: string,
    exclusive: boolean,
  ): Promise<{ accountID: string; sessionID: string; expiresAt: Date }> {
    const hint = await client.query<{ account_id: string }>(
      "SELECT account_id FROM server_sessions WHERE token_digest=$1",
      [sessionDigest(token)],
    );
    const id = hint.rows[0]?.account_id;
    if (!id) throw new IdentityError("unauthenticated");
    const account = await client.query<{
      auth_epoch: string;
      disabled_at: Date | null;
    }>(
      "SELECT auth_epoch,disabled_at FROM accounts WHERE id=$1 " +
        (exclusive ? "FOR UPDATE" : "FOR SHARE"),
      [id],
    );
    if (!account.rows[0] || account.rows[0].disabled_at)
      throw new IdentityError("unauthenticated");
    const session = await client.query<{ id: string; expires_at: Date }>(
      "SELECT id,expires_at FROM server_sessions WHERE token_digest=$1 AND account_id=$2 AND auth_epoch=$3 AND identity_profile_id<>'legacy-disabled' AND revoked_at IS NULL AND expires_at>clock_timestamp() " +
        (exclusive ? "FOR UPDATE" : "FOR SHARE"),
      [sessionDigest(token), id, account.rows[0].auth_epoch],
    );
    if (!session.rows[0]) throw new IdentityError("unauthenticated");
    return {
      accountID: id,
      sessionID: session.rows[0].id,
      expiresAt: session.rows[0].expires_at,
    };
  }
  async logoutAll(token: string): Promise<void> {
    await transaction(this.#pool, this.#schema, async (client) => {
      const current = await this.#session(client, token, true);
      await client.query(
        "UPDATE accounts SET auth_epoch=auth_epoch+1 WHERE id=$1",
        [current.accountID],
      );
      await client.query(
        "UPDATE server_sessions SET revoked_at=COALESCE(revoked_at,clock_timestamp()) WHERE account_id=$1",
        [current.accountID],
      );
      await client.query(
        "INSERT INTO identity_audit(account_id,event) VALUES($1,'logout-all')",
        [current.accountID],
      );
    });
  }
  async deleteAccount(
    token: string,
    receipt: string,
    retentionConfirmation: string,
  ): Promise<void> {
    if (
      retentionConfirmation !== "preserve-owned-libraries" ||
      !/^[A-Za-z0-9_-]{43}$/.test(receipt)
    )
      throw new IdentityError("invalid");
    await transaction(this.#pool, this.#schema, async (client) => {
      const current = await this.#session(client, token, true);
      const proof = await client.query(
        "UPDATE identity_reauthentication SET consumed_at=clock_timestamp() WHERE receipt_digest=$1 AND account_id=$2 AND consumed_at IS NULL AND expires_at>clock_timestamp() RETURNING account_id",
        [sessionDigest(receipt), current.accountID],
      );
      if (!proof.rows[0]) throw new IdentityError("unauthenticated");
      await this.#disable(client, current.accountID, "account-delete");
    });
  }
  async #disable(
    client: PoolClient,
    accountID: string,
    kind: "consent-revoked" | "account-delete",
  ): Promise<void> {
    await client.query(
      "UPDATE accounts SET disabled_at=COALESCE(disabled_at,clock_timestamp()),disabled_reason=$2,tombstoned_at=CASE WHEN $2='account-delete' THEN COALESCE(tombstoned_at,clock_timestamp()) ELSE tombstoned_at END,auth_epoch=auth_epoch+1 WHERE id=$1",
      [accountID, kind],
    );
    await client.query(
      "UPDATE server_sessions SET revoked_at=COALESCE(revoked_at,clock_timestamp()) WHERE account_id=$1",
      [accountID],
    );
    await client.query(
      "UPDATE identity_provider_grants SET state='revocation-pending' WHERE account_id=$1 AND state='retained'",
      [accountID],
    );
    await client.query(
      "UPDATE identity_compensation_jobs SET state='revoke-pending',next_attempt_at=clock_timestamp() WHERE account_id=$1 AND state='retained'",
      [accountID],
    );
    await client.query(
      "INSERT INTO identity_audit(account_id,event) VALUES($1,$2)",
      [accountID, kind === "account-delete" ? "account-delete" : "disabled"],
    );
  }
  async notification(payload: string): Promise<void> {
    const primary = this.#profiles.values().next().value;
    if (!primary) throw new IdentityError("unavailable");
    const proof = await primary.verifier.verifyEvent(payload);
    await this.#event(proof);
  }
  async #event(proof: VerifiedIdentityEvent): Promise<void> {
    assertVerifiedEvent(proof);
    await transaction(this.#pool, this.#schema, async (client) => {
      await this.#capacity(client);
      const duplicate = await client.query(
        "SELECT token_digest FROM identity_events WHERE token_digest=$1 OR (profile_id=$2 AND jti=$3)",
        [
          Buffer.from(proof.tokenDigest, "hex"),
          proof.profileID,
          proof.jti ?? null,
        ],
      );
      if (duplicate.rows.length) return;
      const count = await client.query<{ count: string }>(
        "SELECT count(*) FROM identity_events",
      );
      if (Number(count.rows[0]!.count) >= 100000)
        throw new IdentityError("limited");
      const account = await client.query<{
        id: string;
        disabled_reason: string | null;
      }>(
        "SELECT id,disabled_reason FROM accounts WHERE identity_issuer=$1 AND identity_subject=$2 FOR UPDATE",
        [proof.issuer, proof.subject],
      );
      const row = account.rows[0];
      if (
        row &&
        (proof.kind === "consent-revoked" || proof.kind === "account-delete")
      ) {
        // A deletion tombstone is never downgraded by a later consent event.
        if (row.disabled_reason !== "account-delete")
          await this.#disable(client, row.id, proof.kind);
      }
      await client.query(
        "WITH moment AS MATERIALIZED (SELECT clock_timestamp() AS now) INSERT INTO identity_events(token_digest,profile_id,jti,kind,account_id,processed_at,expires_at) SELECT $1,$2,$3,$4,$5,moment.now,moment.now+interval '25 hours' FROM moment",
        [
          Buffer.from(proof.tokenDigest, "hex"),
          proof.profileID,
          proof.jti ?? null,
          proof.kind,
          row?.id ?? null,
        ],
      );
      await client.query(
        "UPDATE identity_capacity SET event_count=(SELECT count(*) FROM identity_events) WHERE singleton=true",
      );
    });
  }
  async compensate(maximum = 10, signal?: AbortSignal): Promise<number> {
    if (!Number.isInteger(maximum) || maximum < 1 || maximum > 32)
      throw new IdentityError("invalid");
    let processed = 0;
    for (let index = 0; index < maximum; index++) {
      if (signal?.aborted) break;
      const job = await transaction(
        this.#pool,
        this.#schema,
        async (client) => {
          const selected = await client.query<{
            id: string;
            profile_id: string;
            vault_reference: string;
            account_id: string | null;
          }>(
            "SELECT id,profile_id,vault_reference,account_id FROM identity_compensation_jobs WHERE (state IN ('revoke-pending','uncertain') OR (state='provisioning' AND created_at<clock_timestamp()-interval '15 seconds')) AND attempts<3 AND next_attempt_at<=clock_timestamp() AND (lease_until IS NULL OR lease_until<clock_timestamp()) ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1",
          );
          const row = selected.rows[0];
          if (!row) return undefined;
          const lease = randomUUID();
          await client.query(
            "UPDATE identity_compensation_jobs SET lease_id=$2,lease_until=clock_timestamp()+interval '30 seconds',attempts=attempts+1 WHERE id=$1",
            [row.id, lease],
          );
          return { ...row, lease };
        },
      );
      if (!job) break;
      const component = this.#component(job.profile_id),
        controller = new AbortController(),
        timer = setTimeout(() => controller.abort(), 10000);
      const abort = () => controller.abort();
      signal?.addEventListener("abort", abort, { once: true });
      if (signal?.aborted) controller.abort();
      let success = false;
      try {
        const grant = await component.vault.load(
          job.vault_reference,
          controller.signal,
        );
        if (grant.profileID !== job.profile_id)
          throw new IdentityError("unavailable");
        await component.verifier.revoke(grant.refreshToken, controller.signal);
        await component.vault.remove(job.vault_reference, controller.signal);
        success = true;
      } catch {
      } finally {
        clearTimeout(timer);
        signal?.removeEventListener("abort", abort);
      }
      await transaction(this.#pool, this.#schema, async (client) => {
        const updated = await client.query(
          "UPDATE identity_compensation_jobs SET state=$3,lease_id=NULL,lease_until=NULL,next_attempt_at=clock_timestamp()+interval '5 minutes' WHERE id=$1 AND lease_id=$2 RETURNING id",
          [job.id, job.lease, success ? "complete" : "uncertain"],
        );
        if (!updated.rows[0]) return;
        if (success)
          await client.query(
            "UPDATE identity_provider_grants SET state='revoked',revoked_at=clock_timestamp() WHERE vault_reference=$1",
            [job.vault_reference],
          );
        await client.query(
          "INSERT INTO identity_audit(account_id,event) VALUES($1,$2)",
          [job.account_id, success ? "provider-revoked" : "provider-uncertain"],
        );
      });
      processed++;
    }
    return processed;
  }
}
