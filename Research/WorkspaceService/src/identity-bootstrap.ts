import { lstat } from "node:fs/promises";
import { isAbsolute } from "node:path";
import { pathToFileURL } from "node:url";
import type { Pool } from "pg";
import { identityFromEnvironment, IdentityError } from "./identity-config.ts";
import type { IdentityProfile } from "./identity-config.ts";
import type { IdentityVault } from "./identity-vault.ts";
import { OIDCVerifier } from "./oidc-verifier.ts";
import { IdentityStore } from "./identity-store.ts";

/** Administrator code-loading boundary, never selected by HTTP/token claims. */
export async function configuredIdentity(
  pool: Pool,
  schema: string,
  environment: NodeJS.ProcessEnv,
): Promise<IdentityStore | undefined> {
  const profile = identityFromEnvironment(environment);
  if (!profile) return undefined;
  const adapterPath = environment.SCRIPTUM_IDENTITY_VAULT_ADAPTER_MODULE;
  if (!adapterPath || !isAbsolute(adapterPath))
    throw new IdentityError("unavailable");
  try {
    const info = await lstat(adapterPath);
    if (!info.isFile() || info.isSymbolicLink() || (info.mode & 0o022) !== 0)
      throw new IdentityError("unavailable");
    const module = (await import(pathToFileURL(adapterPath).href)) as {
      createIdentityVault?: (
        profile: IdentityProfile,
      ) => Promise<IdentityVault>;
    };
    if (typeof module.createIdentityVault !== "function")
      throw new IdentityError("unavailable");
    const vault = await module.createIdentityVault(profile);
    if (
      !vault ||
      vault.mode !== "production" ||
      vault.reference !== profile.grantVaultReference ||
      ["signClientSecret", "retain", "load", "remove"].some(
        (name) =>
          typeof (vault as unknown as Record<string, unknown>)[name] !==
          "function",
      )
    )
      throw new IdentityError("unavailable");
    return new IdentityStore(pool, schema, [
      { profile, vault, verifier: new OIDCVerifier(profile, vault) },
    ]);
  } catch {
    throw new IdentityError("unavailable");
  }
}
