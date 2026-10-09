import { Pool } from 'pg';
import { WorkspaceStore } from '../src/workspace-store.ts';
import { createGateway, listenGateway } from '../src/http-gateway.ts';

const connectionString = process.env.SCRIPTUM_DATABASE_URL;
const schema = process.env.SCRIPTUM_DATABASE_SCHEMA;
if (!connectionString || !schema) throw new Error('Explicit database URL/schema required; no development fallback');
const pool = new Pool({ connectionString, max: 8, connectionTimeoutMillis: 5000 });
const store = new WorkspaceStore(pool, schema);
const server = createGateway(store);
try {
  if (!await store.isReady()) throw new Error('Workspace schema unavailable');
  const host = process.env.SCRIPTUM_HTTP_HOST ?? '127.0.0.1';
  const port = Number(process.env.SCRIPTUM_HTTP_PORT ?? '8787');
  await listenGateway(server, { host, port, allowExternalBind: process.env.SCRIPTUM_ALLOW_EXTERNAL_BIND === 'YES' });
  console.log('Workspace gateway ready');
  let closing = false;
  async function close(): Promise<void> {
    if (closing) return; closing = true;
    server.closeAllConnections();
    await new Promise<void>(resolve => server.close(() => resolve()));
    await pool.end();
  }
  process.once('SIGTERM', () => { void close(); });
  process.once('SIGINT', () => { void close(); });
} catch {
  await pool.end();
  console.error('Workspace gateway unavailable');
  process.exitCode = 1;
}
