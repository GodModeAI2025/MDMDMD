import type { Pool, PoolClient } from 'pg';
import { schemaIdentifier } from './validation.ts';
export async function transaction<T>(pool: Pool, schema: string, body: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`SET LOCAL search_path TO ${schemaIdentifier(schema)}, pg_catalog`);
    await client.query("SET LOCAL statement_timeout = '5000ms'");
    await client.query("SET LOCAL lock_timeout = '5000ms'");
    const result = await body(client);
    await client.query('COMMIT');
    return result;
  } catch (error) { await client.query('ROLLBACK'); throw error; }
  finally { client.release(); }
}
