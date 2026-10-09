import { Pool } from "pg";
import { importPKCS8, SignJWT } from "jose";
import { IdentityStore } from "../../src/identity-store.ts";
import { identityProfile } from "../../src/identity-config.ts";
import { EncryptedFileIdentityVault } from "../../src/identity-vault.ts";
import { OIDCVerifier } from "../../src/oidc-verifier.ts";

// Private fixture secrets arrive only over owned IPC; never stdout/argv/files.
process.once("message", (value) => {
  // A service listener keeps the real application alive during pool deadlines.
  // This owned child has no HTTP listener, so retain equivalent lifecycle here.
  const lifecycle = setInterval(() => undefined, 1000);
  process.once("uncaughtException", (error) => {
    void report({
      fatal: true,
      code:
        typeof (error as { code?: unknown }).code === "string"
          ? String((error as unknown as { code: string }).code)
              .replace(/[^A-Z0-9_]/g, "")
              .slice(0, 32)
          : "UNCAUGHT",
    }).finally(() => {
      clearInterval(lifecycle);
      process.disconnect();
      process.exitCode = 1;
    });
  });
  const report = (value: object) =>
    new Promise<void>((resolve) => process.send?.(value, () => resolve()));
  void (async () => {
    const data = value as {
      fixture: {
        profile: import("../../src/identity-config.ts").IdentityProfile;
        developerPrivateKey: string;
        vaultEncryptionKey: string;
        vaultRoot: string;
        testCA: string;
      };
      schema: string;
      dto: import("../../src/identity-store.ts").EnrollmentDTO;
      databaseURL: string;
      applicationName: string;
    };
    const profile = identityProfile({
      enabled: true,
      ...data.fixture.profile,
    })!;
    const signingKey = await importPKCS8(
      data.fixture.developerPrivateKey,
      "ES256",
    );
    const vault = new EncryptedFileIdentityVault({
      root: data.fixture.vaultRoot,
      encryptionKey: Buffer.from(data.fixture.vaultEncryptionKey, "base64"),
      reference: profile.grantVaultReference,
      signer: async () =>
        new SignJWT({})
          .setProtectedHeader({ alg: "ES256", kid: profile.keyID })
          .setIssuer(profile.teamID)
          .setAudience(profile.issuer)
          .setSubject(profile.audience)
          .setIssuedAt()
          .setExpirationTime("5m")
          .sign(signingKey),
    });
    const wrapped = {
      mode: vault.mode,
      reference: vault.reference,
      signClientSecret: vault.signClientSecret.bind(vault),
      load: vault.load.bind(vault),
      remove: vault.remove.bind(vault),
      retain: async (
        reference: string,
        grant: Parameters<typeof vault.retain>[1],
        signal: AbortSignal,
      ) => {
        await vault.retain(reference, grant, signal);
        process.send?.({ retained: true });
        await new Promise<void>((resolve) =>
          process.once("message", () => resolve()),
        );
      },
    };
    const pool = new Pool({
      connectionString: data.databaseURL,
      max: 2,
      connectionTimeoutMillis: 500,
      application_name: data.applicationName,
    });
    pool.on("error", () => undefined);
    const verifier = new OIDCVerifier(profile, wrapped, {
      testCA: Buffer.from(data.fixture.testCA, "base64"),
    });
    const store = new IdentityStore(pool, data.schema, [
      { profile, vault: wrapped, verifier },
    ]);
    try {
      await store.enroll(data.dto, "owned-child-fault");
      await report({ unexpectedSuccess: true });
    } catch {
      await report({ failed: true });
    } finally {
      await pool.end();
      clearInterval(lifecycle);
      process.disconnect();
    }
  })().catch(async () => {
    await report({ setupFailed: true });
    clearInterval(lifecycle);
    process.disconnect();
  });
});
