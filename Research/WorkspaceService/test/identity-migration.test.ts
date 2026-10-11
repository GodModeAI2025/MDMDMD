import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID, randomBytes, createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { Pool } from "pg";
import { verificationURL } from "./verification.ts";
import { schemaIdentifier } from "../src/validation.ts";
import { transaction } from "../src/transaction.ts";
import { migrate } from "../src/migrate.ts";

async function legacy(malformed: boolean) {
  const pool = new Pool({
      connectionString: verificationURL(
        process.env.SCRIPTUM_VERIFICATION_DATABASE_URL,
        process.env.SCRIPTUM_ALLOW_VERIFICATION_SCHEMA,
      ),
      max: 4,
      connectionTimeoutMillis: 5000,
    }),
    schema = "wsverify_" + randomUUID().replaceAll("-", "");
  let owned = false;
  const lock = await pool.connect();
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
      "scriptum:identity-migration:" + schema,
    ]);
    await pool.query(`CREATE SCHEMA ${schemaIdentifier(schema)}`);
    owned = true;
    const account = randomUUID(),
      session = randomUUID(),
      library = randomUUID(),
      space = randomUUID(),
      page = randomUUID(),
      key = "synthetic:" + randomUUID(),
      cipher = randomBytes(32),
      nonce = randomBytes(12),
      digest = randomBytes(32),
      revision = randomUUID();
    await transaction(pool, schema, async (client) => {
      for (const [index, name] of [
        "001_workspace.sql",
        "002_nonce_ownership.sql",
      ].entries()) {
        const sql = await readFile(
          new URL("../sql/" + name, import.meta.url),
          "utf8",
        );
        await client.query(sql);
        await client.query(
          "INSERT INTO schema_migrations(version,checksum) VALUES($1,$2)",
          [index + 1, createHash("sha256").update(sql).digest("hex")],
        );
      }
      await client.query(
        "INSERT INTO accounts(id,identity_issuer,identity_subject) VALUES($1,'synthetic-legacy',$2)",
        [account, malformed ? "😀".repeat(100) : "exact-e\u0301"],
      );
      await client.query(
        "INSERT INTO server_sessions(id,account_id,token_digest,expires_at) VALUES($1,$2,$3,clock_timestamp()+interval '1 hour')",
        [session, account, randomBytes(32)],
      );
      await client.query(
        "INSERT INTO libraries(id,owner_account_id,title) VALUES($1,$2,'Preserve')",
        [library, account],
      );
      await client.query(
        "INSERT INTO spaces(library_id,id,title) VALUES($1,$2,'Preserve')",
        [library, space],
      );
      await client.query(
        "INSERT INTO encryption_keys(reference,library_id) VALUES($1,$2)",
        [key, library],
      );
      await client.query(
        "INSERT INTO pages(library_id,space_id,id,revision,source_ciphertext,source_nonce,source_digest,key_reference,envelope_version) VALUES($1,$2,$3,$4,$5,$6,$7,$8,1)",
        [library, space, page, revision, cipher, nonce, digest, key],
      );
    });
    const before = await pool.query(
      `SELECT id,revision,source_ciphertext,source_nonce,source_digest FROM ${schemaIdentifier(schema)}.pages`,
    );
    if (malformed) {
      await assert.rejects(
        migrate(pool, schema),
        (error: unknown) => (error as { code?: string }).code === "23514",
      );
      const columns = await pool.query(
        "SELECT column_name FROM information_schema.columns WHERE table_schema=$1 AND table_name=$2 AND column_name=$3",
        [schema, "accounts", "auth_epoch"],
      );
      assert.equal(columns.rows.length, 0);
      assert.equal(
        (
          await pool.query(
            `SELECT revoked_at FROM ${schemaIdentifier(schema)}.server_sessions WHERE id=$1`,
            [session],
          )
        ).rows[0].revoked_at,
        null,
      );
    } else {
      await migrate(pool, schema);
      await migrate(pool, schema);
      const state = await pool.query(
        `SELECT s.revoked_at,s.identity_profile_id,a.auth_epoch,a.identity_subject FROM ${schemaIdentifier(schema)}.server_sessions s JOIN ${schemaIdentifier(schema)}.accounts a ON a.id=s.account_id WHERE s.id=$1`,
        [session],
      );
      assert.equal(state.rows[0].revoked_at !== null, true);
      assert.equal(state.rows[0].identity_profile_id, "legacy-disabled");
      assert.equal(state.rows[0].identity_subject, "exact-e\u0301");
      await pool.query(
        `UPDATE ${schemaIdentifier(schema)}.schema_migrations SET checksum=repeat('0',64) WHERE version=3`,
      );
      await assert.rejects(migrate(pool, schema));
    }
    assert.deepEqual(
      (
        await pool.query(
          `SELECT id,revision,source_ciphertext,source_nonce,source_digest FROM ${schemaIdentifier(schema)}.pages`,
        )
      ).rows,
      before.rows,
    );
  } finally {
    try {
      if (owned)
        await pool.query(`DROP SCHEMA ${schemaIdentifier(schema)} CASCADE`);
    } finally {
      await lock.query("SELECT pg_advisory_unlock(hashtextextended($1,0))", [
        "scriptum:identity-migration:" + schema,
      ]);
      lock.release();
      await pool.end();
    }
  }
}
test("additive003 cutover revokes legacy sessions and preserves exact account/page bytes", async () => {
  await legacy(false);
});
test("malformed UTF8-byte legacy subject rolls003 back without partial columns or revocation", async () => {
  await legacy(true);
});
