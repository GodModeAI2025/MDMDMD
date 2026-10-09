import { readFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
const configPath = process.env.SCRIPTUM_VERIFICATION_CONFIG_FILE;
if (!configPath) throw new Error('Explicit private verification config file required');
function connectionURLs(value: unknown): string[] {
  if (typeof value === 'string' && /^postgres(?:ql)?:\/\//.test(value)) return [value];
  if (Array.isArray(value)) return value.flatMap(connectionURLs);
  if (value && typeof value === 'object') return Object.values(value).flatMap(connectionURLs);
  return [];
}
const urls = [...new Set(connectionURLs(JSON.parse(await readFile(configPath, 'utf8'))))];
if (urls.length !== 1) throw new Error('Private verification config must contain exactly one database URL');
const child = spawn(process.execPath, ['--test', 'test/http.test.ts'], { stdio: 'inherit', env: { ...process.env, SCRIPTUM_VERIFICATION_DATABASE_URL: urls[0], SCRIPTUM_ALLOW_VERIFICATION_SCHEMA: 'YES' } });
process.exitCode = await new Promise<number>(resolve => child.once('exit', code => resolve(code ?? 1)));
