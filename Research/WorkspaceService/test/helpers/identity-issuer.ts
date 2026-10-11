import { createServer } from "node:https";
import { readFile, stat } from "node:fs/promises";
import { join } from "node:path";
import { randomBytes } from "node:crypto";
import {
  generateKeyPair,
  exportJWK,
  exportPKCS8,
  SignJWT,
  jwtVerify,
} from "jose";
import { identityProfile } from "../../src/identity-config.ts";
import { EncryptedFileIdentityVault } from "../../src/identity-vault.ts";
import { OIDCVerifier } from "../../src/oidc-verifier.ts";

export async function ownedIssuer(
  vaultRoot: string,
  options: { profileID?: string } = {},
) {
  const directory = process.env.SCRIPTUM_TEST_TLS_DIRECTORY;
  if (!directory)
    throw new Error("Explicit owned HTTPS fixture directory required");
  const keyFile = join(directory, "key.pem"),
    cert = await readFile(join(directory, "cert.pem"));
  if ((await stat(keyFile)).mode & 0o077)
    throw new Error("Owned fixture key must be private");
  const rsa = await generateKeyPair("RS256", { extractable: true });
  const developer = await generateKeyPair("ES256", { extractable: true });
  const rotated = await generateKeyPair("RS256", { extractable: true });
  const jwk = {
    ...(await exportJWK(rsa.publicKey)),
    kid: "A",
    use: "sig",
    alg: "RS256",
  };
  const jwkB = {
    ...(await exportJWK(rotated.publicKey)),
    kid: "B",
    use: "sig",
    alg: "RS256",
  };
  const codes = new Map<string, { token: string; refresh: string }>();
  const state = {
    jwksRequests: 0,
    tokenRequests: 0,
    revokeRequests: 0,
    failExchange: false,
    oversizedJWKS: false,
    redirectJWKS: false,
    failJWKS: false,
    slowJWKS: false,
    rotate: false,
    duplicateJWKS: false,
    privateJWKS: false,
    failRevoke: false,
    slowRevoke: false,
    slowToken: false,
    revokeDelayMS: 0,
    tokenAborted: 0,
    revokeAborted: 0,
    activeRevocations: 0,
    maximumRevocations: 0,
  };
  let origin = "";
  const server = createServer(
    { key: await readFile(keyFile), cert },
    (request, response) => {
      if (request.url === "/keys") {
        state.jwksRequests++;
        if (state.redirectJWKS) {
          response.writeHead(302, { location: origin + "/attacker" });
          response.end();
          return;
        }
        if (state.failJWKS) {
          response.writeHead(500);
          response.end("{}");
          return;
        }
        response.setHeader("content-type", "application/json");
        const key = state.rotate ? jwkB : jwk;
        const value = state.oversizedJWKS
          ? "x".repeat(65537)
          : JSON.stringify({
              keys: state.duplicateJWKS
                ? [key, key]
                : [{ ...key, ...(state.privateJWKS ? { d: "AA" } : {}) }],
            });
        if (state.slowJWKS) {
          setTimeout(() => {
            if (!response.destroyed) response.end(value);
          }, 3100);
          return;
        }
        response.end(value);
        return;
      }
      const chunks: Buffer[] = [];
      let size = 0;
      request.on("data", (chunk: Buffer) => {
        size += chunk.length;
        if (size > 32768) {
          request.destroy();
          return;
        }
        chunks.push(chunk);
      });
      request.once("end", () => {
        void (async () => {
          const form = new URLSearchParams(
            Buffer.concat(chunks).toString("utf8"),
          );
          const secret = form.get("client_secret");
          if (!secret) throw new Error("fixture denied");
          await jwtVerify(secret, developer.publicKey, {
            issuer: "fixture-team",
            audience: origin,
            algorithms: ["ES256"],
          });
          if (request.url === "/token") {
            state.tokenRequests++;
            const value = codes.get(form.get("code") ?? "");
            codes.delete(form.get("code") ?? "");
            if (!value || state.failExchange) {
              response.writeHead(400);
              response.end("{}");
              return;
            }
            response.setHeader("content-type", "application/json");
            const tokenBody = JSON.stringify({
              id_token: value.token,
              refresh_token: value.refresh,
              access_token: randomBytes(32).toString("base64url"),
              token_type: "Bearer",
              expires_in: 3600,
            });
            if (state.slowToken) {
              response.once("close", () => {
                if (!response.writableEnded) state.tokenAborted++;
              });
              const timer = setTimeout(() => {
                if (!response.destroyed) response.end(tokenBody);
              }, 5100);
              timer.unref();
              return;
            }
            response.end(tokenBody);
            return;
          }
          if (request.url === "/revoke") {
            state.revokeRequests++;
            state.activeRevocations++;
            state.maximumRevocations = Math.max(
              state.maximumRevocations,
              state.activeRevocations,
            );
            response.once("close", () => {
              state.activeRevocations--;
              if (!response.writableEnded) state.revokeAborted++;
            });
            if (state.failRevoke) {
              response.writeHead(500);
              response.end("{}");
              return;
            }
            if (state.slowRevoke || state.revokeDelayMS) {
              const timer = setTimeout(
                () => {
                  if (!response.destroyed) response.end("{}");
                },
                state.slowRevoke ? 5100 : state.revokeDelayMS,
              );
              timer.unref();
              return;
            }
            response.end("{}");
            return;
          }
          response.writeHead(404);
          response.end();
        })().catch(() => {
          response.writeHead(400);
          response.end("{}");
        });
      });
    },
  );
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  if (!address || typeof address === "string")
    throw new Error("Owned fixture listener missing");
  origin = `https://127.0.0.1:${address.port}`;
  const profile = identityProfile({
    enabled: true,
    mode: "owned-test",
    profileID: options.profileID ?? "owned-profile",
    consentVersion: "test-policy-v1",
    issuer: origin,
    audience: "synthetic-client",
    notificationAudience: "synthetic-notifications",
    jwksURL: origin + "/keys",
    tokenURL: origin + "/token",
    revokeURL: origin + "/revoke",
    teamID: "fixture-team",
    keyID: "fixture-developer-key",
    signingVaultReference: "owned-signing-key",
    grantVaultReference: "owned-grant-vault",
  })!;
  const vaultEncryptionKey = randomBytes(32);
  const vault = new EncryptedFileIdentityVault({
    root: vaultRoot,
    encryptionKey: vaultEncryptionKey,
    reference: profile.grantVaultReference,
    signer: async (_profile, signal) => {
      if (signal.aborted) throw new Error("fixture timeout");
      return new SignJWT({})
        .setProtectedHeader({ alg: "ES256", kid: profile.keyID })
        .setIssuer(profile.teamID)
        .setAudience(profile.issuer)
        .setSubject(profile.audience)
        .setIssuedAt()
        .setExpirationTime("5m")
        .sign(developer.privateKey);
    },
  });
  const verifier = new OIDCVerifier(profile, vault, { testCA: cert });
  async function token(
    nonce: string,
    subject: string,
    extra: Record<string, unknown> = {},
  ) {
    return new SignJWT({ nonce, role: "owner", ...extra })
      .setProtectedHeader({ alg: "RS256", kid: state.rotate ? "B" : "A" })
      .setIssuer(origin)
      .setAudience(profile.audience)
      .setSubject(subject)
      .setIssuedAt()
      .setExpirationTime("5m")
      .sign(state.rotate ? rotated.privateKey : rsa.privateKey);
  }
  async function authorize(
    nonce: string,
    subject: string,
    exchangedSubject = subject,
  ) {
    const authorizationCode = randomBytes(32).toString("base64url"),
      refreshToken = randomBytes(32).toString("base64url");
    codes.set(authorizationCode, {
      token: await token(nonce, exchangedSubject),
      refresh: refreshToken,
    });
    return {
      identityToken: await token(nonce, subject),
      authorizationCode,
      refreshToken,
    };
  }
  async function signed(
    nonce: string,
    subject: string,
    claims: Record<string, unknown> = {},
    headers: Record<string, unknown> = {},
  ) {
    const now = Math.floor(Date.now() / 1000);
    return new SignJWT({
      iss: origin,
      aud: profile.audience,
      sub: subject,
      iat: now,
      exp: now + 300,
      nonce,
      ...claims,
    })
      .setProtectedHeader({
        alg: "RS256",
        kid: state.rotate ? "B" : "A",
        ...headers,
      })
      .sign(state.rotate ? rotated.privateKey : rsa.privateKey);
  }
  async function event(
    subject: string,
    type: string,
    extra: Record<string, unknown> = {},
  ) {
    return new SignJWT({
      iss: origin,
      aud: profile.notificationAudience,
      iat: Math.floor(Date.now() / 1000),
      events: JSON.stringify({
        sub: subject,
        type,
        event_time: Math.floor(Date.now() / 1000),
      }),
      ...extra,
    })
      .setProtectedHeader({ alg: "RS256", kid: "A" })
      .sign(rsa.privateKey);
  }
  async function childFixture() {
    return {
      profile,
      developerPrivateKey: await exportPKCS8(developer.privateKey),
      vaultEncryptionKey: vaultEncryptionKey.toString("base64"),
      vaultRoot,
      testCA: cert.toString("base64"),
    };
  }
  async function close() {
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
  return {
    profile,
    vault,
    verifier,
    state,
    token,
    signed,
    event,
    authorize,
    close,
    childFixture,
  };
}
