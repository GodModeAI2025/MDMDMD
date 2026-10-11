import test from "node:test";
import assert from "node:assert/strict";
import { fork } from "node:child_process";
import type { ChildProcess } from "node:child_process";
import { createServer, createConnection } from "node:net";
import type { Socket } from "node:net";
import { randomUUID, randomBytes } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { Pool } from "pg";
import { ownedIssuer } from "./helpers/identity-issuer.ts";
import { verificationURL } from "./verification.ts";
import { schemaIdentifier } from "../src/validation.ts";
import { migrate } from "../src/migrate.ts";
import { IdentityStore } from "../src/identity-store.ts";
import { IdentityRevocationWorker } from "../src/identity-revocation-worker.ts";

const databaseURL = verificationURL(
  process.env.SCRIPTUM_VERIFICATION_DATABASE_URL,
  process.env.SCRIPTUM_ALLOW_VERIFICATION_SCHEMA,
);
async function fixture<T>(
  body: (value: {
    pool: Pool;
    schema: string;
    issuer: Awaited<ReturnType<typeof ownedIssuer>>;
    identity: IdentityStore;
    root: string;
  }) => Promise<T>,
): Promise<T> {
  const pool = new Pool({
      connectionString: databaseURL,
      max: 6,
      connectionTimeoutMillis: 1000,
    }),
    schema = "wsverify_" + randomUUID().replaceAll("-", ""),
    lock = await pool.connect();
  let owned = false,
    root = "",
    issuer: Awaited<ReturnType<typeof ownedIssuer>> | undefined;
  try {
    assert.equal(
      Math.floor(
        Number(
          (await pool.query("SHOW server_version_num")).rows[0]
            .server_version_num,
        ) / 10000,
      ),
      18,
    );
    await lock.query("SELECT pg_advisory_lock(hashtextextended($1,0))", [
      "scriptum:advanced:" + schema,
    ]);
    await pool.query(`CREATE SCHEMA ${schemaIdentifier(schema)}`);
    owned = true;
    await migrate(pool, schema);
    root = await mkdtemp("/private/tmp/scriptum-identity-advanced-");
    issuer = await ownedIssuer(join(root, "vault"));
    const identity = new IdentityStore(pool, schema, [issuer]);
    return await body({ pool, schema, issuer, identity, root });
  } finally {
    if (issuer) await issuer.close();
    if (root) await rm(root, { recursive: true, force: true });
    try {
      if (owned)
        await pool.query(`DROP SCHEMA ${schemaIdentifier(schema)} CASCADE`);
    } finally {
      await lock.query("SELECT pg_advisory_unlock(hashtextextended($1,0))", [
        "scriptum:advanced:" + schema,
      ]);
      lock.release();
      await pool.end();
    }
  }
}
async function waitUntil(
  predicate: () => Promise<boolean> | boolean,
  timeout = 2000,
) {
  const start = Date.now();
  while (!(await predicate())) {
    if (Date.now() - start > timeout) throw new Error("Owned fixture deadline");
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}
async function childMessage(
  child: ChildProcess,
  name: string,
  timeout = 10000,
): Promise<void> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error("Owned child barrier deadline"));
    }, timeout);
    const message = (value: unknown) => {
      if (
        value &&
        typeof value === "object" &&
        ("setupFailed" in value ||
          "unexpectedSuccess" in value ||
          "fatal" in value)
      ) {
        cleanup();
        reject(
          new Error(
            "Owned child result: " +
              Object.keys(value)
                .filter((key) =>
                  [
                    "setupFailed",
                    "unexpectedSuccess",
                    "fatal",
                    "phase",
                    "code",
                  ].includes(key),
                )
                .join(","),
          ),
        );
        return;
      }
      if (value && typeof value === "object" && name in value) {
        cleanup();
        resolve();
      }
    };
    const exited = () => {
      cleanup();
      reject(
        new Error(
          "Owned child exited before barrier (code=" +
            child.exitCode +
            ",signal=" +
            child.signalCode +
            ")",
        ),
      );
    };
    function cleanup() {
      clearTimeout(timer);
      child.off("message", message);
      child.off("exit", exited);
    }
    child.on("message", message);
    child.once("exit", exited);
  });
}
async function stopChild(child: ChildProcess) {
  if (child.exitCode !== null || child.signalCode !== null) return;
  const exited = new Promise<void>((resolve) =>
    child.once("exit", () => resolve()),
  );
  child.kill("SIGKILL");
  await Promise.race([
    exited,
    new Promise<never>((_resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error("Owned child exit deadline")),
        2000,
      );
      timer.unref();
    }),
  ]);
}
async function proxy() {
  const sockets = new Set<Socket>(),
    target = new URL(databaseURL),
    server = createServer((inbound) => {
      sockets.add(inbound);
      const outbound = createConnection({
        host: target.hostname,
        port: Number(target.port || 5432),
      });
      sockets.add(outbound);
      inbound.on("error", () => outbound.destroy());
      outbound.on("error", () => inbound.destroy());
      inbound.on("close", () => {
        sockets.delete(inbound);
        outbound.destroy();
      });
      outbound.on("close", () => {
        sockets.delete(outbound);
        inbound.destroy();
      });
      inbound.pipe(outbound);
      outbound.pipe(inbound);
    });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  if (!address || typeof address === "string")
    throw new Error("Owned proxy unavailable");
  const childURL = new URL(databaseURL);
  childURL.port = String(address.port);
  let closed = false;
  return {
    url: childURL.href,
    close: async () => {
      if (closed) return;
      closed = true;
      for (const socket of sockets) socket.destroy();
      await new Promise<void>((resolve) => server.close(() => resolve()));
    },
  };
}
async function retainedFault(kind: "kill" | "database-loss") {
  await fixture(async ({ pool, schema, issuer, identity }) => {
    const challenge = await identity.challenge(
        issuer.profile.profileID,
        issuer.profile.consentVersion,
        "advanced-child",
      ),
      authorization = await issuer.authorize(
        challenge.nonce,
        "owned-fault-subject",
      ),
      dto = {
        challengeID: challenge.challengeID,
        challengeSecret: challenge.challengeSecret,
        state: challenge.state,
        identityToken: authorization.identityToken,
        authorizationCode: authorization.authorizationCode,
      };
    const transport = kind === "database-loss" ? await proxy() : undefined;
    const child = fork(
      fileURLToPath(
        new URL("./helpers/identity-fault-child.ts", import.meta.url),
      ),
      [],
      {
        stdio: ["ignore", "ignore", "ignore", "ipc"],
        env: { ...process.env, SCRIPTUM_VERIFICATION_DATABASE_URL: undefined },
        serialization: "advanced",
      },
    );
    try {
      const retained = childMessage(child, "retained");
      child.send({
        fixture: await issuer.childFixture(),
        schema,
        dto,
        databaseURL: transport?.url ?? databaseURL,
        applicationName: "owned-identity-fault-" + randomUUID(),
      });
      await retained;
      const jobs = await pool.query<{
        id: string;
        vault_reference: string;
        state: string;
      }>(
        `SELECT id,vault_reference,state FROM ${schemaIdentifier(schema)}.identity_compensation_jobs WHERE challenge_id=$1`,
        [challenge.challengeID],
      );
      assert.equal(jobs.rows.length, 1);
      assert.equal(jobs.rows[0]!.state, "provisioning");
      assert.equal(
        (
          await issuer.vault.load(
            jobs.rows[0]!.vault_reference,
            new AbortController().signal,
          )
        ).profileID,
        issuer.profile.profileID,
      );
      if (kind === "kill") await stopChild(child);
      else {
        await transport!.close();
        const failed = childMessage(child, "failed");
        child.send({ continue: true });
        await failed;
        await waitUntil(
          () => child.exitCode !== null || child.signalCode !== null,
          2000,
        );
      }
      const fresh = new IdentityStore(pool, schema, [issuer]);
      await assert.rejects(fresh.enroll(dto, "advanced-replay"));
      assert.equal(
        (
          await pool.query(
            `SELECT id FROM ${schemaIdentifier(schema)}.accounts WHERE identity_subject='owned-fault-subject'`,
          )
        ).rows.length,
        0,
      );
      assert.equal(
        (
          await pool.query(
            `SELECT count(*) FROM ${schemaIdentifier(schema)}.server_sessions`,
          )
        ).rows[0].count,
        "0",
      );
      await pool.query(
        `UPDATE ${schemaIdentifier(schema)}.identity_compensation_jobs SET created_at=clock_timestamp()-interval '16 seconds',next_attempt_at=clock_timestamp() WHERE id=$1`,
        [jobs.rows[0]!.id],
      );
      const before = issuer.state.revokeRequests;
      await fresh.compensate(1);
      assert.equal(issuer.state.revokeRequests, before + 1);
      assert.equal(
        (
          await pool.query(
            `SELECT state FROM ${schemaIdentifier(schema)}.identity_compensation_jobs WHERE id=$1`,
            [jobs.rows[0]!.id],
          )
        ).rows[0].state,
        "complete",
      );
      await assert.rejects(
        issuer.vault.load(
          jobs.rows[0]!.vault_reference,
          new AbortController().signal,
        ),
      );
    } finally {
      await stopChild(child);
      await transport?.close();
    }
  });
}
test("actual child SIGKILL after durable vault retention recovers without account/session publication", async () => {
  await retainedFault("kill");
});
test("complete owned-child database transport interruption preserves recoverable orphan", async () => {
  await retainedFault("database-loss");
});
async function deleted(
  identity: IdentityStore,
  issuer: Awaited<ReturnType<typeof ownedIssuer>>,
  subject: string,
) {
  const challenge = await identity.challenge(
      issuer.profile.profileID,
      issuer.profile.consentVersion,
      subject,
    ),
    authorization = await issuer.authorize(challenge.nonce, subject),
    session = await identity.enroll(
      {
        challengeID: challenge.challengeID,
        challengeSecret: challenge.challengeSecret,
        state: challenge.state,
        identityToken: authorization.identityToken,
        authorizationCode: authorization.authorizationCode,
      },
      subject,
    );
  await identity.deleteAccount(
    session.sessionToken,
    session.reauthenticationReceipt,
    "preserve-owned-libraries",
  );
  return session;
}
test("two independent overlapping workers respect durable lease and make one provider request", async () => {
  await fixture(async ({ pool, schema, issuer, identity }) => {
    const session = await deleted(identity, issuer, "overlap-subject");
    issuer.state.revokeDelayMS = 200;
    const second = new IdentityStore(pool, schema, [issuer]),
      a = new IdentityRevocationWorker(identity, {
        intervalMS: 10,
        maximumJobs: 1,
      }),
      b = new IdentityRevocationWorker(second, {
        intervalMS: 10,
        maximumJobs: 1,
      });
    try {
      a.start();
      await waitUntil(() => issuer.state.revokeRequests === 1);
      b.start();
      await waitUntil(() => b.status.cycles > 0);
      const leased = (
        await pool.query(
          `SELECT id,lease_id,attempts,state FROM ${schemaIdentifier(schema)}.identity_compensation_jobs WHERE account_id=$1`,
          [session.accountID],
        )
      ).rows[0];
      assert.equal(leased.attempts, 1);
      assert.ok(leased.lease_id);
      assert.equal(
        (
          await pool.query(
            `UPDATE ${schemaIdentifier(schema)}.identity_compensation_jobs SET state='complete' WHERE id=$1 AND lease_id=$2 RETURNING id`,
            [leased.id, randomUUID()],
          )
        ).rows.length,
        0,
      );
      await waitUntil(async () => {
        return (
          (
            await pool.query(
              `SELECT state FROM ${schemaIdentifier(schema)}.identity_compensation_jobs WHERE id=$1`,
              [leased.id],
            )
          ).rows[0].state === "complete"
        );
      });
      assert.equal(issuer.state.revokeRequests, 1);
      assert.equal(issuer.state.maximumRevocations, 1);
    } finally {
      await a.stop();
      await b.stop();
    }
  });
});
test("stopping during real slow revocation cancels socket and persists uncertain state without more cycles", async () => {
  await fixture(async ({ pool, schema, issuer, identity }) => {
    const session = await deleted(identity, issuer, "shutdown-subject");
    issuer.state.slowRevoke = true;
    const worker = new IdentityRevocationWorker(identity, {
      intervalMS: 10,
      maximumJobs: 1,
    });
    worker.start();
    await waitUntil(() => issuer.state.revokeRequests === 1);
    const began = Date.now();
    await worker.stop();
    assert.equal(Date.now() - began < 1500, true);
    await waitUntil(() => issuer.state.revokeAborted === 1);
    const state = (
      await pool.query(
        `SELECT state,lease_id,attempts FROM ${schemaIdentifier(schema)}.identity_compensation_jobs WHERE account_id=$1`,
        [session.accountID],
      )
    ).rows[0];
    assert.equal(state.state, "uncertain");
    assert.equal(state.lease_id, null);
    assert.equal(state.attempts, 1);
    const cycles = worker.status.cycles;
    await new Promise((resolve) => setTimeout(resolve, 50));
    assert.equal(worker.status.cycles, cycles);
    assert.equal(issuer.state.revokeRequests, 1);
  });
});

test("separate real HTTPS token and revoke deadlines cancel sockets and never retry automatically", async () => {
  await fixture(async ({ issuer, identity }) => {
    const challenge = await identity.challenge(
        issuer.profile.profileID,
        issuer.profile.consentVersion,
        "slow-token",
      ),
      authorization = await issuer.authorize(
        challenge.nonce,
        "slow-token-subject",
      );
    issuer.state.slowToken = true;
    const began = Date.now();
    await assert.rejects(
      identity.enroll(
        {
          challengeID: challenge.challengeID,
          challengeSecret: challenge.challengeSecret,
          state: challenge.state,
          identityToken: authorization.identityToken,
          authorizationCode: authorization.authorizationCode,
        },
        "slow-token",
      ),
    );
    const elapsed = Date.now() - began;
    assert.equal(elapsed >= 4500 && elapsed < 6500, true);
    await waitUntil(() => issuer.state.tokenAborted === 1);
    assert.equal(issuer.state.tokenRequests, 1);
    issuer.state.slowToken = false;
    issuer.state.slowRevoke = true;
    const revokeStart = Date.now();
    await assert.rejects(
      issuer.verifier.revoke(
        randomBytes(32).toString("base64url"),
        new AbortController().signal,
      ),
    );
    assert.equal(
      Date.now() - revokeStart >= 4500 && Date.now() - revokeStart < 6500,
      true,
    );
    await waitUntil(() => issuer.state.revokeAborted === 1);
    assert.equal(issuer.state.revokeRequests, 1);
  });
});
