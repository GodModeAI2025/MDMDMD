import { readFile } from "node:fs/promises";
import { spawn } from "node:child_process";
const path = process.env.SCRIPTUM_VERIFICATION_CONFIG_FILE;
if (!path || !process.env.SCRIPTUM_TEST_TLS_DIRECTORY)
  throw new Error(
    "Explicit owned PostgreSQL/TLS verification configuration required",
  );
function urls(value: unknown): string[] {
  if (typeof value === "string" && /^postgres(?:ql)?:\/\//.test(value))
    return [value];
  if (Array.isArray(value)) return value.flatMap(urls);
  if (value && typeof value === "object")
    return Object.values(value).flatMap(urls);
  return [];
}
const values = [...new Set(urls(JSON.parse(await readFile(path, "utf8"))))];
if (values.length !== 1)
  throw new Error("One private verification URL required");
const child = spawn(
  process.execPath,
  [
    "--test",
    "test/identity-http-postgres.test.ts",
    "test/identity-migration.test.ts",
  ],
  {
    stdio: "inherit",
    env: {
      ...process.env,
      SCRIPTUM_VERIFICATION_DATABASE_URL: values[0],
      SCRIPTUM_ALLOW_VERIFICATION_SCHEMA: "YES",
    },
  },
);
process.exitCode = await new Promise<number>((resolve) =>
  child.once("exit", (code) => resolve(code ?? 1)),
);
