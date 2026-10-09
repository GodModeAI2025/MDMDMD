import { readFile } from "node:fs/promises";
import { spawn } from "node:child_process";
const config = process.env.SCRIPTUM_VERIFICATION_CONFIG_FILE;
if (!config || !process.env.SCRIPTUM_TEST_TLS_DIRECTORY)
  throw new Error(
    "Explicit owned PostgreSQL/TLS configuration required for complete verification",
  );
function urls(value: unknown): string[] {
  if (typeof value === "string" && /^postgres(?:ql)?:\/\//.test(value))
    return [value];
  if (Array.isArray(value)) return value.flatMap(urls);
  if (value && typeof value === "object")
    return Object.values(value).flatMap(urls);
  return [];
}
const found = [...new Set(urls(JSON.parse(await readFile(config, "utf8"))))];
if (found.length !== 1)
  throw new Error("Exactly one private verification database URL required");
const child = spawn("npm", ["test"], {
  stdio: "inherit",
  env: {
    ...process.env,
    SCRIPTUM_VERIFICATION_DATABASE_URL: found[0],
    SCRIPTUM_ALLOW_VERIFICATION_SCHEMA: "YES",
  },
});
process.exitCode = await new Promise<number>((resolve) =>
  child.once("exit", (code) => resolve(code ?? 1)),
);
