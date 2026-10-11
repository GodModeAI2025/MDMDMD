import test from "node:test";
import assert from "node:assert/strict";
import { randomBytes, createHash, randomUUID } from "node:crypto";
import { mkdtemp, rm, readdir, stat, readFile } from "node:fs/promises";
import { join } from "node:path";
import { ownedIssuer } from "./helpers/identity-issuer.ts";
import { OIDCVerifier, assertVerifiedIdentity } from "../src/oidc-verifier.ts";

test("real HTTPS native verification/code exchange and encrypted retained grant", async () => {
  const root = await mkdtemp("/private/tmp/scriptum-identity-");
  const issuer = await ownedIssuer(join(root, "vault"));
  try {
    const nonce = randomBytes(32).toString("base64url"),
      context = {
        challengeID: randomUUID(),
        attemptID: randomUUID(),
        nonceDigest: createHash("sha256").update(nonce).digest(),
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + 300000),
      };
    const authorization = await issuer.authorize(nonce, "synthetic-subject");
    const proof = await issuer.verifier.verifyAndRedeem(
      context,
      authorization.identityToken,
      authorization.authorizationCode,
      new AbortController().signal,
    );
    assertVerifiedIdentity(proof);
    assert.equal(proof.subject, "synthetic-subject");
    assert.equal(issuer.state.tokenRequests, 1);
    const reference = "grant:" + randomUUID();
    await issuer.vault.retain(
      reference,
      {
        profileID: proof.profileID,
        identityDigest: proof.identityDigest,
        refreshToken: proof.refreshToken,
      },
      new AbortController().signal,
    );
    const file = join(root, "vault", (await readdir(join(root, "vault")))[0]!);
    assert.equal((await stat(file)).mode & 0o777, 0o600);
    assert.equal(
      (await readFile(file)).includes(Buffer.from(proof.refreshToken)),
      false,
    );
    assert.equal(
      (await issuer.vault.load(reference, new AbortController().signal))
        .identityDigest,
      proof.identityDigest,
    );
    await assert.rejects(
      issuer.verifier.verifyAndRedeem(
        context,
        authorization.identityToken,
        authorization.authorizationCode,
        new AbortController().signal,
      ),
    );
  } finally {
    await issuer.close();
    await rm(root, { recursive: true, force: true });
  }
});
test("nonce/exchanged subject mismatch and TLS/redirect/oversize fail closed", async () => {
  const root = await mkdtemp("/private/tmp/scriptum-identity-");
  const issuer = await ownedIssuer(join(root, "vault"));
  try {
    const nonce = randomBytes(32).toString("base64url"),
      context = {
        challengeID: randomUUID(),
        attemptID: randomUUID(),
        nonceDigest: createHash("sha256").update(nonce).digest(),
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + 300000),
      };
    const mismatch = await issuer.authorize(
      nonce,
      "native-subject",
      "other-subject",
    );
    await assert.rejects(
      issuer.verifier.verifyAndRedeem(
        context,
        mismatch.identityToken,
        mismatch.authorizationCode,
        new AbortController().signal,
      ),
    );
    const wrongNonce = await issuer.authorize("wrong-nonce", "native-subject");
    await assert.rejects(
      issuer.verifier.verifyAndRedeem(
        context,
        wrongNonce.identityToken,
        wrongNonce.authorizationCode,
        new AbortController().signal,
      ),
    );
    const noTrust = new OIDCVerifier(issuer.profile, issuer.vault),
      authorization = await issuer.authorize(nonce, "native-subject");
    await assert.rejects(
      noTrust.verifyAndRedeem(
        context,
        authorization.identityToken,
        authorization.authorizationCode,
        new AbortController().signal,
      ),
    );
    issuer.state.oversizedJWKS = true;
    const oversized = new OIDCVerifier(issuer.profile, issuer.vault, {
      testCA: await readFile(
        join(process.env.SCRIPTUM_TEST_TLS_DIRECTORY!, "cert.pem"),
      ),
    });
    await assert.rejects(
      oversized.verifyAndRedeem(
        context,
        authorization.identityToken,
        authorization.authorizationCode,
        new AbortController().signal,
      ),
    );
    issuer.state.oversizedJWKS = false;
    issuer.state.redirectJWKS = true;
    const redirect = new OIDCVerifier(issuer.profile, issuer.vault, {
      testCA: await readFile(
        join(process.env.SCRIPTUM_TEST_TLS_DIRECTORY!, "cert.pem"),
      ),
    });
    await assert.rejects(
      redirect.verifyAndRedeem(
        context,
        authorization.identityToken,
        authorization.authorizationCode,
        new AbortController().signal,
      ),
    );
  } finally {
    await issuer.close();
    await rm(root, { recursive: true, force: true });
  }
});

test("configured resolver rotates, shares fetch, honors cooldown and never uses expired cache", async () => {
  const root = await mkdtemp("/private/tmp/scriptum-identity-"),
    issuer = await ownedIssuer(join(root, "vault"));
  try {
    const cert = await readFile(
      join(process.env.SCRIPTUM_TEST_TLS_DIRECTORY!, "cert.pem"),
    );
    const verifier = new OIDCVerifier(issuer.profile, issuer.vault, {
      testCA: cert,
      testTimings: { cooldownDuration: 40, cacheMaxAge: 100 },
    });
    const nonce = randomBytes(32).toString("base64url"),
      context = {
        challengeID: randomUUID(),
        attemptID: randomUUID(),
        nonceDigest: createHash("sha256").update(nonce).digest(),
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + 300000),
      };
    const first = await issuer.authorize(nonce, "rotation");
    await verifier.verifyAndRedeem(
      context,
      first.identityToken,
      first.authorizationCode,
      new AbortController().signal,
    );
    assert.equal(issuer.state.jwksRequests, 1);
    issuer.state.rotate = true;
    const rotated = await issuer.authorize(nonce, "rotation");
    await assert.rejects(
      verifier.verifyAndRedeem(
        context,
        rotated.identityToken,
        rotated.authorizationCode,
        new AbortController().signal,
      ),
    );
    assert.equal(issuer.state.jwksRequests, 1);
    await new Promise((resolve) => setTimeout(resolve, 50));
    const a = await issuer.authorize(nonce, "rotation"),
      b = await issuer.authorize(nonce, "rotation");
    await Promise.all([
      verifier.verifyAndRedeem(
        context,
        a.identityToken,
        a.authorizationCode,
        new AbortController().signal,
      ),
      verifier.verifyAndRedeem(
        context,
        b.identityToken,
        b.authorizationCode,
        new AbortController().signal,
      ),
    ]);
    assert.equal(issuer.state.jwksRequests, 2);
    await new Promise((resolve) => setTimeout(resolve, 110));
    issuer.state.failJWKS = true;
    const expired = await issuer.authorize(nonce, "rotation");
    await assert.rejects(
      verifier.verifyAndRedeem(
        context,
        expired.identityToken,
        expired.authorizationCode,
        new AbortController().signal,
      ),
    );
    assert.equal(issuer.state.jwksRequests, 3);
  } finally {
    await issuer.close();
    await rm(root, { recursive: true, force: true });
  }
});
test("wrong/future claims, token-selected key URLs and malformed public key sets deny without exchange", async () => {
  const root = await mkdtemp("/private/tmp/scriptum-identity-"),
    issuer = await ownedIssuer(join(root, "vault"));
  try {
    const nonce = randomBytes(32).toString("base64url"),
      context = {
        challengeID: randomUUID(),
        attemptID: randomUUID(),
        nonceDigest: createHash("sha256").update(nonce).digest(),
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + 300000),
      },
      now = Math.floor(Date.now() / 1000);
    for (const claims of [
      { aud: ["synthetic-client"] },
      { iss: "https://attacker.invalid" },
      { iat: now + 120 },
      { exp: now - 1 },
      { iat: now - 400 },
      { sub: "" },
    ]) {
      const bad = await issuer.signed(nonce, "claims", claims);
      await assert.rejects(
        issuer.verifier.verifyAndRedeem(
          context,
          bad,
          "unused",
          new AbortController().signal,
        ),
      );
    }
    const selected = await issuer.signed(
      nonce,
      "claims",
      {},
      { jku: "https://attacker.invalid" },
    );
    await assert.rejects(
      issuer.verifier.verifyAndRedeem(
        context,
        selected,
        "unused",
        new AbortController().signal,
      ),
    );
    assert.equal(issuer.state.tokenRequests, 0);
    const cert = await readFile(
      join(process.env.SCRIPTUM_TEST_TLS_DIRECTORY!, "cert.pem"),
    );
    issuer.state.duplicateJWKS = true;
    const auth = await issuer.authorize(nonce, "claims");
    await assert.rejects(
      new OIDCVerifier(issuer.profile, issuer.vault, {
        testCA: cert,
      }).verifyAndRedeem(
        context,
        auth.identityToken,
        auth.authorizationCode,
        new AbortController().signal,
      ),
    );
    issuer.state.duplicateJWKS = false;
    issuer.state.privateJWKS = true;
    await assert.rejects(
      new OIDCVerifier(issuer.profile, issuer.vault, {
        testCA: cert,
      }).verifyAndRedeem(
        context,
        auth.identityToken,
        auth.authorizationCode,
        new AbortController().signal,
      ),
    );
  } finally {
    await issuer.close();
    await rm(root, { recursive: true, force: true });
  }
});

test("real streaming deadline aborts slow issuer and tampered vault ciphertext fails authentication", async () => {
  const root = await mkdtemp("/private/tmp/scriptum-identity-"),
    issuer = await ownedIssuer(join(root, "vault"));
  try {
    const nonce = randomBytes(32).toString("base64url"),
      context = {
        challengeID: randomUUID(),
        attemptID: randomUUID(),
        nonceDigest: createHash("sha256").update(nonce).digest(),
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + 300000),
      },
      authorization = await issuer.authorize(nonce, "timeout");
    issuer.state.slowJWKS = true;
    const began = Date.now();
    await assert.rejects(
      issuer.verifier.verifyAndRedeem(
        context,
        authorization.identityToken,
        authorization.authorizationCode,
        new AbortController().signal,
      ),
    );
    assert.equal(Date.now() - began < 4500, true);
    assert.equal(issuer.state.tokenRequests, 0);
    issuer.state.slowJWKS = false;
    const reference = "grant:" + randomUUID(),
      grant = {
        profileID: issuer.profile.profileID,
        identityDigest: "a".repeat(64),
        refreshToken: randomBytes(32).toString("base64url"),
      };
    await issuer.vault.retain(reference, grant, new AbortController().signal);
    const file = join(root, "vault", reference.slice(6) + ".vault"),
      bytes = await readFile(file);
    bytes[bytes.length - 1] = bytes[bytes.length - 1]! ^ 1;
    const { writeFile } = await import("node:fs/promises");
    await writeFile(file, bytes, { mode: 0o600 });
    await assert.rejects(
      issuer.vault.load(reference, new AbortController().signal),
    );
  } finally {
    await issuer.close();
    await rm(root, { recursive: true, force: true });
  }
});
