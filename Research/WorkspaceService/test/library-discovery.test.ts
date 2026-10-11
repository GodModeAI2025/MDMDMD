import test, { before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID, randomBytes } from "node:crypto";
import { setTimeout as delay } from "node:timers/promises";
import { Pool } from "pg";
import type { PoolClient, QueryResult } from "pg";
import { migrate } from "../src/migrate.ts";
import { WorkspaceStore, sessionDigest } from "../src/workspace-store.ts";
import { createGateway, listenGateway } from "../src/http-gateway.ts";
import { schemaIdentifier } from "../src/validation.ts";
import { verificationURL } from "./verification.ts";

const connectionString = verificationURL(
  process.env.SCRIPTUM_VERIFICATION_DATABASE_URL,
  process.env.SCRIPTUM_ALLOW_VERIFICATION_SCHEMA,
);
const schema = "wsverify_" + randomUUID().replaceAll("-", "");
const sql = schemaIdentifier(schema);
const pool = new Pool({ connectionString, max: 8, application_name: schema });
const store = new WorkspaceStore(pool, schema);
const gateway = createGateway(store);
const queries: { text: string; rows: number }[] = [];
let base: string,
  owned = false,
  suiteLock: PoolClient | undefined;
// Observe actual pg results; no mock database, rank or permission substitute.
pool.on("connect", (client) => {
  const original = client.query.bind(client);
  client.query = ((...args: unknown[]) => {
    const text =
      typeof args[0] === "string"
        ? args[0]
        : ((args[0] as { text?: string })?.text ?? "");
    const result = Reflect.apply(original, client, args);
    if (result && typeof result.then === "function") {
      return result.then((reply: QueryResult | QueryResult[]) => {
        const rows = Array.isArray(reply)
          ? reply.reduce((count, item) => count + (item.rows?.length ?? 0), 0)
          : (reply.rows?.length ?? 0);
        queries.push({ text, rows });
        return reply;
      });
    }
    return result;
  }) as typeof client.query;
});

async function identity() {
  const id = randomUUID(),
    token = randomBytes(32).toString("base64url"),
    sessionID = randomUUID();
  await pool.query(
    `INSERT INTO ${sql}.accounts(id,identity_issuer,identity_subject) VALUES($1,'owned-discovery-verification',$2)`,
    [id, id],
  );
  await pool.query(
    `INSERT INTO ${sql}.server_sessions(id,account_id,token_digest,expires_at,identity_profile_id,auth_epoch) VALUES($1,$2,$3,clock_timestamp()+interval '1 hour','synthetic-verification-only',0)`,
    [sessionID, id, sessionDigest(token)],
  );
  return { id, token, sessionID };
}
async function get(path: string, token: string) {
  return fetch(base + path, { headers: { authorization: "Bearer " + token } });
}
async function sharedLibraries(count: number, accountID: string, role = 1) {
  const owner = await identity(),
    ids: string[] = [];
  for (let i = 0; i < count; i++) {
    const id = await store.createLibrary(owner.token, "Owned discovery " + i);
    await store.setMembership(
      owner.token,
      { libraryID: id, kind: "library" },
      accountID,
      role as 1 | 2 | 3,
    );
    ids.push(id);
  }
  return { owner, ids: ids.sort() };
}
async function page(response: Response) {
  assert.equal(response.status, 200, "Authenticated library GET must exist");
  assert.equal(response.headers.get("cache-control"), "no-store");
  return (await response.json()) as {
    libraries: { libraryID: string; title: string; role: string }[];
    nextAfter: string | null;
  };
}
async function untilLibraryBlocked(pending: () => boolean) {
  for (let i = 0; i < 100 && !pending(); i++) {
    const blocked = await pool.query(
      `SELECT 1 FROM pg_stat_activity WHERE application_name=$1 AND wait_event_type='Lock' AND query ILIKE '%libraries%'`,
      [schema],
    );
    if (blocked.rowCount) return;
    await delay(10);
  }
  assert.fail(
    "Discovery did not reach its real library lock before completing",
  );
}

before(async () => {
  const version = await pool.query<{ server_version_num: string }>(
    "SHOW server_version_num",
  );
  assert.equal(
    Math.floor(Number(version.rows[0]!.server_version_num) / 10000),
    18,
  );
  suiteLock = await pool.connect();
  await suiteLock.query("SELECT pg_advisory_lock(hashtextextended($1,0))", [
    "scriptum:discovery-verification:" + schema,
  ]);
  await pool.query(`CREATE SCHEMA ${sql}`);
  owned = true;
  await migrate(pool, schema);
  base = await listenGateway(gateway);
});
after(async () => {
  gateway.closeAllConnections();
  await new Promise<void>((resolve) => gateway.close(() => resolve()));
  try {
    if (owned) await pool.query(`DROP SCHEMA ${sql} CASCADE`);
  } finally {
    suiteLock?.release();
    await pool.end();
  }
});

test("WD01 owned and root-shared libraries only, exact viewer/editor/owner permissions", async () => {
  const viewer = await identity(),
    owner = await identity();
  const ownedID = await store.createLibrary(viewer.token, "Own exact title");
  const shared = await sharedLibraries(3, viewer.id);
  await store.setMembership(
    shared.owner.token,
    { libraryID: shared.ids[1]!, kind: "library" },
    viewer.id,
    2,
  );
  await store.setMembership(
    shared.owner.token,
    { libraryID: shared.ids[2]!, kind: "library" },
    viewer.id,
    3,
  );
  const hidden = await store.createLibrary(owner.token, "Hidden parent title");
  const child = await store.createSpace(
    owner.token,
    hidden,
    "Only shared child",
  );
  await store.setMembership(
    owner.token,
    { libraryID: hidden, spaceID: child, kind: "space" },
    viewer.id,
    1,
  );
  const result = await page(await get("/libraries", viewer.token));
  assert.deepEqual(
    result.libraries.map((row) => row.libraryID),
    [ownedID, ...shared.ids].sort(),
  );
  assert.equal(
    result.libraries.find((row) => row.libraryID === ownedID)?.role,
    "owner",
  );
  assert.equal(
    result.libraries.find((row) => row.libraryID === shared.ids[1])?.role,
    "editor",
  );
  assert.equal(
    result.libraries.find((row) => row.libraryID === shared.ids[2])?.role,
    "owner",
  );
  assert.equal(result.nextAfter, null);
  assert.deepEqual(Object.keys(result).sort(), ["libraries", "nextAfter"]);
  assert.ok(
    result.libraries.every(
      (row) => Object.keys(row).sort().join(",") === "libraryID,role,title",
    ),
  );
  assert.equal((await get(`/libraries/${hidden}`, viewer.token)).status, 404);
});

test("WD02 root delegation ceiling caps permission and sessions deny revocation/epoch/tombstone", async () => {
  const viewer = await identity(),
    shared = await sharedLibraries(1, viewer.id, 3),
    id = shared.ids[0]!;
  await pool.query(
    `UPDATE ${sql}.libraries SET delegation_ceiling=1 WHERE id=$1`,
    [id],
  );
  const response = await get(`/libraries/${id}`, viewer.token);
  assert.equal(response.status, 200, "Authenticated metadata GET must exist");
  assert.deepEqual(await response.json(), {
    libraryID: id,
    title: "Owned discovery 0",
    role: "viewer",
  });
  await pool.query(
    `UPDATE ${sql}.server_sessions SET revoked_at=clock_timestamp() WHERE id=$1`,
    [viewer.sessionID],
  );
  assert.equal((await get("/libraries", viewer.token)).status, 401);
  const disabled = await identity();
  await pool.query(
    `UPDATE ${sql}.accounts SET disabled_at=clock_timestamp(),disabled_reason='account-delete',tombstoned_at=clock_timestamp(),auth_epoch=auth_epoch+1 WHERE id=$1`,
    [disabled.id],
  );
  assert.equal((await get("/libraries", disabled.token)).status, 401);
  const stale = await identity();
  await pool.query(`UPDATE ${sql}.accounts SET auth_epoch=1 WHERE id=$1`, [
    stale.id,
  ]);
  assert.equal((await get("/libraries", stale.token)).status, 401);
});

test("WD03 eight-row UUID keyset pages, strict cursor/query and bounded escaped titles", async () => {
  const viewer = await identity(),
    shared = await sharedLibraries(17, viewer.id);
  const title = "\u0001".repeat(4096);
  await pool.query(
    `UPDATE ${sql}.libraries SET title=$1 WHERE id=ANY($2::uuid[])`,
    [title, shared.ids],
  );
  const seen: string[] = [];
  let cursor: string | null = null;
  do {
    const response = await get(
      "/libraries" + (cursor ? "?after=" + cursor : ""),
      viewer.token,
    );
    assert.equal(response.status, 200, "Authenticated listing GET must exist");
    const bytes = Buffer.from(await response.arrayBuffer());
    assert.ok(bytes.length <= 256 * 1024);
    const reply = JSON.parse(bytes.toString("utf8"));
    assert.ok(reply.libraries.length <= 8);
    assert.ok(
      reply.libraries.every((row: { title: string }) => row.title === title),
    );
    seen.push(
      ...reply.libraries.map((row: { libraryID: string }) => row.libraryID),
    );
    if (reply.nextAfter) assert.ok(!cursor || reply.nextAfter > cursor);
    cursor = reply.nextAfter;
  } while (cursor);
  assert.deepEqual(seen, shared.ids);
  for (const query of [
    "?after=bad",
    "?after=" + shared.ids[0] + "&after=" + shared.ids[1],
    "?limit=999",
    "?accountID=" + viewer.id,
  ]) {
    assert.equal((await get("/libraries" + query, viewer.token)).status, 400);
  }
});

test("WD04 unknown/inaccessible IDs same redacted404 and no parent from page grants", async () => {
  const viewer = await identity(),
    owner = await identity();
  const visible = await store.createLibrary(viewer.token, "Visible");
  assert.equal(
    (await get(`/libraries/${visible}`, viewer.token)).status,
    200,
    "Single library GET must exist",
  );
  const hidden = await store.createLibrary(
    owner.token,
    "Never disclose this parent",
  );
  const spaceID = await store.createSpace(
      owner.token,
      hidden,
      "Owned page scope",
    ),
    pageID = randomUUID();
  const keyReference = "owned-discovery:" + randomUUID();
  await pool.query(
    `INSERT INTO ${sql}.encryption_keys(reference,library_id) VALUES($1,$2)`,
    [keyReference, hidden],
  );
  await store.createPage(
    owner.token,
    { libraryID: hidden, spaceID, pageID },
    {
      ciphertext: randomBytes(64),
      nonce: randomBytes(12),
      digest: randomBytes(32),
      keyReference,
      version: 1,
    },
  );
  await store.setMembership(
    owner.token,
    { libraryID: hidden, spaceID, pageID, kind: "page" },
    viewer.id,
    1,
  );
  const listed = await page(await get("/libraries", viewer.token));
  assert.deepEqual(
    listed.libraries.map((row) => row.libraryID),
    [visible],
  );
  const missing = await get(`/libraries/${randomUUID()}`, viewer.token),
    denied = await get(`/libraries/${hidden}`, viewer.token);
  assert.equal(missing.status, 404);
  assert.equal(denied.status, 404);
  assert.equal(await missing.text(), await denied.text());
  assert.equal(
    (await get("/libraries", randomBytes(32).toString("base64url"))).status,
    401,
  );
});

test("WD06 many child memberships stay out of bounded root queries/candidate materialization", async () => {
  const viewer = await identity(),
    shared = await sharedLibraries(10, viewer.id),
    id = shared.ids[0]!;
  await pool.query(
    `INSERT INTO ${sql}.spaces(library_id,id,title) SELECT $1,gen_random_uuid(),'Owned child' FROM generate_series(1,300)`,
    [id],
  );
  await pool.query(
    `INSERT INTO ${sql}.memberships(id,library_id,account_id,resource_kind,space_id,role_rank) SELECT gen_random_uuid(),library_id,$2,'space',id,1 FROM ${sql}.spaces WHERE library_id=$1`,
    [id, viewer.id],
  );
  queries.length = 0;
  const reply = await page(await get("/libraries", viewer.token));
  assert.equal(reply.libraries.length, 8);
  const membershipReads = queries.filter(
    (query) => /SELECT/i.test(query.text) && /memberships/i.test(query.text),
  );
  assert.ok(membershipReads.length > 0);
  assert.ok(
    membershipReads.every((query) =>
      /resource_kind\s*=\s*'library'/i.test(query.text),
    ),
    "Every membership read is root-only",
  );
  assert.ok(
    membershipReads.every((query) => query.rows <= 9),
    "No unbounded child collection reaches JavaScript",
  );
  const candidates = membershipReads.filter((query) =>
    /LIMIT\s+9\b/i.test(query.text),
  );
  assert.equal(candidates.length, 1, "Exactly one SQL-bounded candidate read");
  assert.ok(
    !/\btitle\b/i.test(candidates[0]!.text),
    "Candidate selection cannot fetch titles before locks",
  );
});

test("WD02 membership revocation while library lock held is rechecked, empty page cursor advances", async () => {
  const viewer = await identity(),
    shared = await sharedLibraries(9, viewer.id),
    held = await pool.connect();
  let settled = false;
  try {
    await held.query("BEGIN");
    await held.query(`SELECT id FROM ${sql}.libraries WHERE id=$1 FOR UPDATE`, [
      shared.ids[0],
    ]);
    const pending = get("/libraries", viewer.token).then((reply) => {
      settled = true;
      return reply;
    });
    await untilLibraryBlocked(() => settled);
    await held.query(
      `DELETE FROM ${sql}.memberships WHERE account_id=$1 AND library_id=ANY($2::uuid[])`,
      [viewer.id, shared.ids.slice(0, 8)],
    );
    await held.query("COMMIT");
    const reply = await page(await pending);
    assert.deepEqual(reply.libraries, []);
    assert.equal(reply.nextAfter, shared.ids[7]);
    const next = await page(
      await get("/libraries?after=" + reply.nextAfter, viewer.token),
    );
    assert.deepEqual(
      next.libraries.map((row) => row.libraryID),
      [shared.ids[8]],
    );
  } finally {
    await held.query("ROLLBACK");
    held.release();
  }
});

test("WD02 session expiry during held library lock is rechecked before title disclosure", async () => {
  const viewer = await identity(),
    shared = await sharedLibraries(1, viewer.id),
    id = shared.ids[0]!;
  assert.equal(
    (await get(`/libraries/${id}`, viewer.token)).status,
    200,
    "Library metadata route must exist",
  );
  const held = await pool.connect();
  let settled = false;
  try {
    await pool.query(
      `UPDATE ${sql}.server_sessions SET expires_at=clock_timestamp()+interval '300 milliseconds' WHERE id=$1`,
      [viewer.sessionID],
    );
    await held.query("BEGIN");
    await held.query(`SELECT id FROM ${sql}.libraries WHERE id=$1 FOR UPDATE`, [
      id,
    ]);
    const pending = get(`/libraries/${id}`, viewer.token).then((reply) => {
      settled = true;
      return reply;
    });
    await untilLibraryBlocked(() => settled);
    await delay(400);
    await held.query("COMMIT");
    const response = await pending;
    assert.equal(response.status, 401);
    assert.ok(!(await response.text()).includes("Owned discovery"));
  } finally {
    await held.query("ROLLBACK");
    held.release();
  }
});
