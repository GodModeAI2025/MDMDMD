import { randomUUID } from "node:crypto";
import type { Pool } from "pg";
import type { PageAddress } from "../../src/workspace-store.ts";
import type { EncryptedEnvelope } from "../../src/validation.ts";
import { transaction } from "../../src/transaction.ts";
/** Direct SQL bootstrap/readback of OWNED pre-identity fixtures, never auth admission. */
export function legacyFixturePages(
  pool: Pool,
  schema: string,
  accountID: string,
) {
  return {
    async createLibrary(_token: string, title: string) {
      return transaction(pool, schema, async (client) => {
        const id = randomUUID();
        await client.query(
          "INSERT INTO libraries(id,owner_account_id,title) VALUES($1,$2,$3)",
          [id, accountID, title],
        );
        return id;
      });
    },
    async createSpace(_token: string, libraryID: string, title: string) {
      return transaction(pool, schema, async (client) => {
        const id = randomUUID();
        await client.query(
          "INSERT INTO spaces(library_id,id,title) VALUES($1,$2,$3)",
          [libraryID, id, title],
        );
        return id;
      });
    },
    async createPage(
      _token: string,
      target: PageAddress,
      value: EncryptedEnvelope,
    ) {
      return transaction(pool, schema, async (client) => {
        const revision = randomUUID();
        await client.query(
          "INSERT INTO pages(library_id,space_id,id,revision,source_ciphertext,source_nonce,source_digest,key_reference,envelope_version) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)",
          [
            target.libraryID,
            target.spaceID,
            target.pageID,
            revision,
            value.ciphertext,
            value.nonce,
            value.digest,
            value.keyReference,
            value.version,
          ],
        );
        return revision;
      });
    },
    async readPage(_token: string, target: PageAddress) {
      return transaction(pool, schema, async (client) => {
        const row = (
          await client.query(
            "SELECT revision,source_ciphertext,source_nonce,source_digest,key_reference,envelope_version FROM pages WHERE library_id=$1 AND space_id=$2 AND id=$3",
            [target.libraryID, target.spaceID, target.pageID],
          )
        ).rows[0];
        if (!row) throw new Error("Owned legacy fixture missing");
        return {
          revision: String(row.revision),
          envelope: {
            ciphertext: row.source_ciphertext as Buffer,
            nonce: row.source_nonce as Buffer,
            digest: row.source_digest as Buffer,
            keyReference: String(row.key_reference),
            version: row.envelope_version as 1,
          },
        };
      });
    },
    async writePage(
      _token: string,
      target: PageAddress,
      expected: string,
      value: EncryptedEnvelope,
    ) {
      return transaction(pool, schema, async (client) => {
        await client.query("SELECT id FROM libraries WHERE id=$1 FOR UPDATE", [
          target.libraryID,
        ]);
        await client.query(
          "INSERT INTO page_revisions(library_id,space_id,page_id,revision,source_ciphertext,source_nonce,source_digest,key_reference,envelope_version) SELECT library_id,space_id,id,revision,source_ciphertext,source_nonce,source_digest,key_reference,envelope_version FROM pages WHERE library_id=$1 AND space_id=$2 AND id=$3 AND revision=$4",
          [target.libraryID, target.spaceID, target.pageID, expected],
        );
        const revision = randomUUID();
        const result = await client.query(
          "UPDATE pages SET revision=$4,source_ciphertext=$5,source_nonce=$6,source_digest=$7,key_reference=$8,envelope_version=$9 WHERE library_id=$1 AND space_id=$2 AND id=$3 AND revision=$10",
          [
            target.libraryID,
            target.spaceID,
            target.pageID,
            revision,
            value.ciphertext,
            value.nonce,
            value.digest,
            value.keyReference,
            value.version,
            expected,
          ],
        );
        if (result.rowCount !== 1)
          throw new Error("Owned legacy fixture conflict");
        return revision;
      });
    },
  };
}
