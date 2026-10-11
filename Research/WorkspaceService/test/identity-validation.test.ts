import test from "node:test";
import assert from "node:assert/strict";
import {
  identityProfile,
  identityFromEnvironment,
} from "../src/identity-config.ts";
import { inspectCompactToken } from "../src/oidc-verifier.ts";
test("identity disabled/missing deployment configuration never produces enrollment", () => {
  assert.equal(identityProfile({ enabled: false }), undefined);
  assert.throws(() => identityProfile({ enabled: true }));
});
test("compact JWT syntax rejects duplicate claims, padding and token-selected URLs before verification", () => {
  const token = (header: string, payload: string) =>
    Buffer.from(header).toString("base64url") +
    "." +
    Buffer.from(payload).toString("base64url") +
    "." +
    Buffer.alloc(256).toString("base64url");
  assert.throws(() =>
    inspectCompactToken(
      token('{"alg":"RS256","kid":"k","jku":"https://attacker.invalid"}', "{}"),
    ),
  );
  assert.throws(() =>
    inspectCompactToken(
      token('{"alg":"RS256","kid":"k"}', '{"sub":"a","sub":"b"}'),
    ),
  );
  assert.throws(() =>
    inspectCompactToken(token('{"alg":"none","kid":"k"}', "{}")),
  );
});

test("production environment never admits test mode or inconsistent profile byte bounds", () => {
  assert.throws(() =>
    identityFromEnvironment({
      SCRIPTUM_IDENTITY_ENABLED: "true",
      SCRIPTUM_IDENTITY_MODE: "owned-test",
    }),
  );
  assert.throws(() =>
    identityFromEnvironment({ SCRIPTUM_IDENTITY_ENABLED: "true" }),
  );
  const fields = {
    enabled: true,
    mode: "owned-test" as const,
    profileID: "p",
    consentVersion: "v",
    issuer: "https://127.0.0.1:1",
    audience: "a",
    notificationAudience: "n",
    jwksURL: "https://127.0.0.1:1/keys",
    tokenURL: "https://127.0.0.1:1/token",
    revokeURL: "https://127.0.0.1:1/revoke",
    teamID: "t",
    keyID: "k",
    signingVaultReference: "s",
    grantVaultReference: "g",
  };
  assert.throws(() =>
    identityProfile({ ...fields, profileID: "x".repeat(129) }),
  );
  assert.throws(() =>
    identityProfile({ ...fields, consentVersion: "x".repeat(129) }),
  );
  assert.throws(() => identityProfile({ ...fields, profileID: "p q" }));
});

test("production adapter missing callable capability fails startup without a network request", async () => {
  const { mkdtemp, writeFile, rm } = await import("node:fs/promises"),
    { join } = await import("node:path"),
    { Pool } = await import("pg"),
    { configuredIdentity } = await import("../src/identity-bootstrap.ts");
  const root = await mkdtemp("/private/tmp/scriptum-identity-adapter-"),
    file = join(root, "adapter.mjs"),
    pool = new Pool();
  try {
    await writeFile(
      file,
      "export async function createIdentityVault(){return {mode:'production',reference:'synthetic-grant-reference',signClientSecret(){}}}",
      { mode: 0o600 },
    );
    const environment = {
      SCRIPTUM_IDENTITY_ENABLED: "true",
      SCRIPTUM_IDENTITY_PROFILE_ID: "synthetic-profile",
      SCRIPTUM_IDENTITY_CONSENT_VERSION: "v1",
      SCRIPTUM_OIDC_ISSUER: "https://appleid.apple.com",
      SCRIPTUM_OIDC_AUDIENCE: "synthetic.audience",
      SCRIPTUM_OIDC_JWKS_URL: "https://appleid.apple.com/auth/keys",
      SCRIPTUM_OIDC_TOKEN_URL: "https://appleid.apple.com/auth/token",
      SCRIPTUM_OIDC_REVOKE_URL: "https://appleid.apple.com/auth/revoke",
      SCRIPTUM_OIDC_ALLOWED_ALGORITHMS: "RS256",
      SCRIPTUM_APPLE_TEAM_ID: "AAAAAAAAAA",
      SCRIPTUM_APPLE_KEY_ID: "BBBBBBBBBB",
      SCRIPTUM_APPLE_PRIVATE_KEY_VAULT_REFERENCE: "synthetic-signing-reference",
      SCRIPTUM_IDENTITY_GRANT_VAULT_REFERENCE: "synthetic-grant-reference",
      SCRIPTUM_APPLE_NOTIFICATION_AUDIENCE: "synthetic.notifications",
      SCRIPTUM_IDENTITY_VAULT_ADAPTER_MODULE: file,
    };
    await assert.rejects(configuredIdentity(pool, "unused", environment));
    assert.equal(await configuredIdentity(pool, "unused", {}), undefined);
  } finally {
    await pool.end();
    await rm(root, { recursive: true, force: true });
  }
});
