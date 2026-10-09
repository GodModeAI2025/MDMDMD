import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import type { Pool } from "pg";
import { transaction } from "./transaction.ts";
import { schemaIdentifier } from "./validation.ts";
export async function migrate(pool: Pool, schema: string): Promise<void> {
  const names = [
    "001_workspace.sql",
    "002_nonce_ownership.sql",
    "003_identity.sql",
  ];
  const migrations = await Promise.all(
    names.map(async (name, index) => {
      const sql = await readFile(
        new URL("../sql/" + name, import.meta.url),
        "utf8",
      );
      return {
        version: index + 1,
        sql,
        checksum: createHash("sha256").update(sql).digest("hex"),
      };
    }),
  );
  await transaction(pool, schema, async (client) => {
    await client.query(
      "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
      ["scriptum:migration:" + schema],
    );
    await client.query(
      `CREATE SCHEMA IF NOT EXISTS ${schemaIdentifier(schema)}`,
    );
    const existing = await client.query<{ present: string | null }>(
      "SELECT to_regclass($1) AS present",
      [schema + ".schema_migrations"],
    );
    const versions = existing.rows[0]?.present
      ? (
          await client.query<{ version: number; checksum: string }>(
            "SELECT version,checksum FROM schema_migrations ORDER BY version",
          )
        ).rows
      : [];
    for (let index = 0; index < versions.length; index++) {
      const stored = versions[index],
        expected = migrations[index];
      if (
        !stored ||
        !expected ||
        stored.version !== expected.version ||
        stored.checksum !== expected.checksum
      )
        throw new Error("Migration version/checksum mismatch");
    }
    for (const migration of migrations.slice(versions.length)) {
      await client.query(migration.sql);
      await client.query(
        "INSERT INTO schema_migrations(version,checksum) VALUES($1,$2)",
        [migration.version, migration.checksum],
      );
    }
  });
}
