import { Pool } from "pg";
import { migrate } from "../src/migrate.ts";
const connectionString = process.env.SCRIPTUM_DATABASE_URL,
  schema = process.env.SCRIPTUM_DATABASE_SCHEMA;
if (!connectionString || !schema)
  throw new Error("Explicit configured database URL/schema required");
const pool = new Pool({ connectionString });
try {
  await migrate(pool, schema);
  console.log("Migration verified");
} finally {
  await pool.end();
}
