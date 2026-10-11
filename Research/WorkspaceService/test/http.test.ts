import test, { before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID, randomBytes } from "node:crypto";
import { request } from "node:http";
import { Pool } from "pg";
import type { PoolClient } from "pg";
import { migrate } from "../src/migrate.ts";
import { WorkspaceStore, sessionDigest } from "../src/workspace-store.ts";
import { schemaIdentifier } from "../src/validation.ts";
import { createGateway, listenGateway } from "../src/http-gateway.ts";
import { verificationURL } from "./verification.ts";

const connectionString = verificationURL(
  process.env.SCRIPTUM_VERIFICATION_DATABASE_URL,
  process.env.SCRIPTUM_ALLOW_VERIFICATION_SCHEMA,
);
const schema = "wsverify_" + randomUUID().replaceAll("-", "");
const pool = new Pool({ connectionString, max: 8 });
const store = new WorkspaceStore(pool, schema);
const gateway = createGateway(store, { maximumBodyBytes: 1024 });
let lock: PoolClient | undefined,
  owned = false,
  base: string,
  owner: string,
  viewer: string,
  viewerID: string,
  pagePath: string,
  revision: string,
  keyReference: string;
const wire = () => ({
  ciphertext: randomBytes(64).toString("base64"),
  nonce: randomBytes(12).toString("base64"),
  digest: randomBytes(32).toString("base64"),
  keyReference,
  version: 1,
});
async function identity() {
  const id = randomUUID(),
    token = randomBytes(32).toString("base64url");
  await pool.query(
    `INSERT INTO ${schemaIdentifier(schema)}.accounts(id,identity_issuer,identity_subject) VALUES($1,'synthetic-http',$2)`,
    [id, id],
  );
  await pool.query(
    `INSERT INTO ${schemaIdentifier(schema)}.server_sessions(id,account_id,token_digest,expires_at,identity_profile_id,auth_epoch) VALUES($1,$2,$3,clock_timestamp()+interval '1 hour','synthetic-verification-only',0)`,
    [randomUUID(), id, sessionDigest(token)],
  );
  return { id, token };
}
async function call(
  path: string,
  method = "GET",
  token = owner,
  body?: unknown,
  headers: Record<string, string> = {},
) {
  return fetch(base + path, {
    method,
    headers: {
      authorization: "Bearer " + token,
      ...(body === undefined ? {} : { "content-type": "application/json" }),
      ...headers,
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}
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
    "scriptum:http-verification:" + schema,
  ]);
  await pool.query(`CREATE SCHEMA ${schemaIdentifier(schema)}`);
  owned = true;
  await migrate(pool, schema);
  owner = (await identity()).token;
  const v = await identity();
  viewer = v.token;
  viewerID = v.id;
  const library = await store.createLibrary(owner, "HTTP"),
    space = await store.createSpace(owner, library, "HTTP");
  keyReference = "synthetic:http:" + randomUUID();
  await pool.query(
    `INSERT INTO ${schemaIdentifier(schema)}.encryption_keys(reference,library_id) VALUES($1,$2)`,
    [keyReference, library],
  );
  const page = randomUUID(),
    value = wire();
  revision = await store.createPage(
    owner,
    { libraryID: library, spaceID: space, pageID: page },
    {
      ciphertext: Buffer.from(value.ciphertext, "base64"),
      nonce: Buffer.from(value.nonce, "base64"),
      digest: Buffer.from(value.digest, "base64"),
      keyReference,
      version: 1,
    },
  );
  await store.setMembership(
    owner,
    { libraryID: library, kind: "library" },
    viewerID,
    1,
  );
  pagePath = `/libraries/${library}/spaces/${space}/pages/${page}`;
  base = await listenGateway(gateway);
});
after(async () => {
  gateway.closeAllConnections();
  await new Promise<void>((resolve) => gateway.close(() => resolve()));
  try {
    if (owned)
      await pool.query(`DROP SCHEMA ${schemaIdentifier(schema)} CASCADE`);
  } finally {
    if (lock) {
      try {
        await lock.query("SELECT pg_advisory_unlock(hashtextextended($1,0))", [
          "scriptum:http-verification:" + schema,
        ]);
      } finally {
        lock.release();
      }
    }
    await pool.end();
  }
});
test("health/readiness, opaque authentication and default no CORS", async () => {
  const health = await fetch(base + "/health");
  assert.equal(health.status, 200);
  assert.deepEqual(await health.json(), { status: "ok" });
  assert.equal(health.headers.get("access-control-allow-origin"), null);
  assert.equal((await fetch(base + "/ready")).status, 200);
  assert.equal((await fetch(base + pagePath)).status, 401);
  assert.equal(
    (await call(pagePath, "GET", randomBytes(32).toString("base64url"))).status,
    401,
  );
  assert.equal((await call(pagePath, "OPTIONS")).status, 405);
});
test("real encrypted read and revision-bound CAS preserve bytes on conflict", async () => {
  const original = await call(pagePath);
  assert.equal(original.status, 200);
  assert.equal(original.headers.get("etag"), `"${revision}"`);
  const value = wire(),
    updated = await call(pagePath, "PUT", owner, value, {
      "if-match": `"${revision}"`,
    });
  assert.equal(updated.status, 200);
  const result = (await updated.json()) as { revision: string };
  const stale = await call(pagePath, "PUT", owner, wire(), {
    "if-match": `"${revision}"`,
  });
  assert.equal(stale.status, 409);
  const current = (await (await call(pagePath)).json()) as {
    revision: string;
    envelope: unknown;
  };
  assert.equal(current.revision, result.revision);
  assert.deepEqual(current.envelope, value);
  revision = result.revision;
});
test("viewer denial and missing resources have identical private error policy", async () => {
  const denied = await call(pagePath, "PUT", viewer, wire(), {
    "if-match": `"${revision}"`,
  });
  const absent = await call(pagePath.replace(/[^/]+$/, randomUUID()));
  assert.equal(denied.status, 404);
  assert.equal(absent.status, 404);
  assert.deepEqual(await denied.json(), await absent.json());
});
test("strict media/JSON/fields/base64/If-Match and query routing", async () => {
  assert.equal(
    (
      await call("/libraries", "POST", owner, {
        title: "x",
        accountID: randomUUID(),
        role: "owner",
      })
    ).status,
    400,
  );
  assert.equal(
    (
      await call(
        "/libraries",
        "POST",
        owner,
        { title: "x" },
        { "content-type": "text/plain" },
      )
    ).status,
    415,
  );
  assert.equal((await call(pagePath + "?account=other")).status, 400);
  assert.equal(
    (await call(pagePath, "PUT", owner, wire(), { "if-match": revision }))
      .status,
    400,
  );
  assert.equal(
    (
      await call(
        pagePath,
        "PUT",
        owner,
        { ...wire(), nonce: "%%%invalid" },
        { "if-match": `"${revision}"` },
      )
    ).status,
    400,
  );
  const duplicate = await fetch(base + "/libraries", {
    method: "POST",
    headers: {
      authorization: "Bearer " + owner,
      "content-type": "application/json",
    },
    body: '{"title":"a","title":"b"}',
  });
  assert.equal(duplicate.status, 400);
});
test("SQL nonce/key errors are controlled and never leak database details", async () => {
  const current = (await (await call(pagePath)).json()) as {
    envelope: ReturnType<typeof wire>;
  };
  const bad = await call(
    pagePath,
    "PUT",
    owner,
    { ...wire(), nonce: current.envelope.nonce },
    { "if-match": `"${revision}"` },
  );
  assert.equal(bad.status, 409);
  const text = await bad.text();
  assert.doesNotMatch(
    text,
    /SELECT|UPDATE|nonce_usage|constraint|23505|synthetic|Bearer/i,
  );
  const unknown = await call(
    pagePath,
    "PUT",
    owner,
    { ...wire(), keyReference: "foreign:unknown" },
    { "if-match": `"${revision}"` },
  );
  assert.equal(unknown.status, 400);
  assert.equal(
    ((await (await call(pagePath)).json()) as { revision: string }).revision,
    revision,
  );
});
test("oversized chunk body is bounded and connection closes after 413", async () => {
  const status = await new Promise<number>((resolve, reject) => {
    const req = request(
      base + "/libraries",
      {
        method: "POST",
        headers: {
          authorization: "Bearer " + owner,
          "content-type": "application/json",
        },
      },
      (res) => {
        res.resume();
        resolve(res.statusCode ?? 0);
      },
    );
    req.on("error", reject);
    req.setTimeout(3000, () => req.destroy(new Error("HTTP test deadline")));
    req.write("x".repeat(600));
    req.write("x".repeat(600));
    req.end();
  });
  assert.equal(status, 413);
});
test("logout really revokes its server session and expiry denies access", async () => {
  const expired = await identity();
  await pool.query(
    `UPDATE ${schemaIdentifier(schema)}.server_sessions SET expires_at=clock_timestamp()-interval '1 second' WHERE token_digest=$1`,
    [sessionDigest(expired.token)],
  );
  assert.equal((await call(pagePath, "GET", expired.token)).status, 401);
  assert.equal((await call("/session/logout", "POST", viewer)).status, 204);
  assert.equal((await call(pagePath, "GET", viewer)).status, 401);
});

test("aborted responses retain concurrency slots until real handlers settle", async () => {
  let entered!: () => void,
    release!: () => void,
    active = 0,
    maximum = 0;
  const started = new Promise<void>((resolve) => {
    entered = resolve;
  });
  const barrier = new Promise<void>((resolve) => {
    release = resolve;
  });
  class DelayedStore extends WorkspaceStore {
    override async readPage(
      token: string,
      target: import("../src/workspace-store.ts").PageAddress,
    ) {
      active++;
      maximum = Math.max(maximum, active);
      entered();
      try {
        await barrier;
        return await super.readPage(token, target);
      } finally {
        active--;
      }
    }
  }
  const delayed = createGateway(new DelayedStore(pool, schema), {
    maximumConcurrentRequests: 1,
  });
  const url = await listenGateway(delayed),
    abort = new AbortController();
  const first = fetch(url + pagePath, {
    headers: { authorization: "Bearer " + owner },
    signal: abort.signal,
  }).catch(() => undefined);
  let second: Promise<Response | undefined> | undefined;
  try {
    await started;
    abort.abort();
    await new Promise((resolve) => setTimeout(resolve, 20));
    second = fetch(url + pagePath, {
      headers: { authorization: "Bearer " + owner },
    }).catch(() => undefined);
    await new Promise((resolve) => setTimeout(resolve, 20));
    assert.equal(
      maximum,
      1,
      "Closed responses must not uncount still-running handlers",
    );
    release();
    const response = await second;
    assert.equal(response?.status, 503);
    await first;
  } finally {
    release();
    await second;
    await first;
    for (let attempt = 0; active > 0 && attempt < 600; attempt++)
      await new Promise((resolve) => setTimeout(resolve, 10));
    assert.equal(
      active,
      0,
      "Owned delayed handlers must settle before schema cleanup",
    );
    delayed.closeAllConnections();
    await new Promise<void>((resolve) => delayed.close(() => resolve()));
  }
});

test("owner HTTP create/space/page and grant/revoke routes use only session authority", async () => {
  const created = await call("/libraries", "POST", owner, {
    title: "HTTP-created",
  });
  assert.equal(created.status, 201);
  const libraryID = ((await created.json()) as { libraryID: string }).libraryID;
  const space = await call(`/libraries/${libraryID}/spaces`, "POST", owner, {
    title: "HTTP space",
  });
  assert.equal(space.status, 201);
  const spaceID = ((await space.json()) as { spaceID: string }).spaceID;
  const registered = "synthetic:http:" + randomUUID();
  await pool.query(
    `INSERT INTO ${schemaIdentifier(schema)}.encryption_keys(reference,library_id) VALUES($1,$2)`,
    [registered, libraryID],
  );
  const target = `/libraries/${libraryID}/spaces/${spaceID}/pages/${pagePath.split("/").at(-1)}`;
  const value = { ...wire(), keyReference: registered },
    page = await call(target, "POST", owner, value);
  assert.equal(page.status, 201);
  const guest = await identity();
  assert.equal((await call(target, "GET", guest.token)).status, 404);
  const membership = `/libraries/${libraryID}/memberships/${guest.id}`;
  assert.equal(
    (await call(membership, "PUT", owner, { role: "viewer" })).status,
    204,
  );
  assert.equal((await call(target, "GET", guest.token)).status, 200);
  assert.equal(
    (await call(membership, "PUT", guest.token, { role: "owner" })).status,
    404,
  );
  assert.equal((await call(membership, "DELETE", owner)).status, 204);
  assert.equal((await call(target, "GET", guest.token)).status, 404);
  assert.notDeepEqual(
    ((await (await call(target)).json()) as { envelope: unknown }).envelope,
    ((await (await call(pagePath)).json()) as { envelope: unknown }).envelope,
  );
});
