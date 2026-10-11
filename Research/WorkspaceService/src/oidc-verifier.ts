import { createHash, timingSafeEqual } from "node:crypto";
import { createRemoteJWKSet, customFetch, jwtVerify } from "jose";
import type { JWTPayload } from "jose";
import { parseJSON } from "./http-wire.ts";
import { IdentityError } from "./identity-config.ts";
import type { IdentityProfile } from "./identity-config.ts";
import { IdentityNetwork } from "./identity-network.ts";
import type { IdentityVault } from "./identity-vault.ts";

const brand: unique symbol = Symbol("server-verified-identity");
const proofs = new WeakSet<object>();
export interface VerifiedIdentity {
  readonly [brand]: true;
  readonly profileID: string;
  readonly issuer: string;
  readonly subject: string;
  readonly audience: string;
  readonly challengeID: string;
  readonly attemptID: string;
  readonly refreshToken: string;
  readonly identityDigest: string;
}
const eventBrand: unique symbol = Symbol("server-verified-event");
const events = new WeakSet<object>();
export interface VerifiedIdentityEvent {
  readonly [eventBrand]: true;
  readonly profileID: string;
  readonly issuer: string;
  readonly subject: string;
  readonly tokenDigest: string;
  readonly jti?: string;
  readonly kind:
    "consent-revoked" | "account-delete" | "email-enabled" | "email-disabled";
}
export function assertVerifiedEvent(event: VerifiedIdentityEvent): void {
  if (!events.has(event)) throw new IdentityError("unauthenticated");
}
export interface ChallengeProofContext {
  challengeID: string;
  attemptID: string;
  nonceDigest: Buffer;
  createdAt: Date;
  expiresAt: Date;
}
export function assertVerifiedIdentity(proof: VerifiedIdentity): void {
  if (!proofs.has(proof)) throw new IdentityError("unauthenticated");
}
function decode(value: string, maximum: number): Buffer {
  if (
    !value ||
    !/^[A-Za-z0-9_-]+$/.test(value) ||
    value.length > Math.ceil((maximum * 4) / 3)
  )
    throw new IdentityError("unauthenticated");
  const bytes = Buffer.from(value, "base64url");
  if (bytes.length > maximum || bytes.toString("base64url") !== value)
    throw new IdentityError("unauthenticated");
  return bytes;
}
export function inspectCompactToken(token: string): {
  header: Record<string, unknown>;
  claims: Record<string, unknown>;
} {
  try {
    if (typeof token !== "string" || Buffer.byteLength(token) > 16384)
      throw new IdentityError("unauthenticated");
    const parts = token.split(".");
    if (parts.length !== 3) throw new IdentityError("unauthenticated");
    const header = parseJSON(
      new TextDecoder("utf-8", { fatal: true }).decode(decode(parts[0]!, 1024)),
      { maximumDepth: 8, maximumNodes: 32 },
    );
    const claims = parseJSON(
      new TextDecoder("utf-8", { fatal: true }).decode(decode(parts[1]!, 8192)),
      { maximumDepth: 8, maximumNodes: 32 },
    );
    decode(parts[2]!, 2048);
    if (
      header.alg !== "RS256" ||
      typeof header.kid !== "string" ||
      !header.kid ||
      Buffer.byteLength(header.kid) > 128 ||
      Object.keys(header).some((key) => !["alg", "kid", "typ"].includes(key)) ||
      (header.typ !== undefined && header.typ !== "JWT")
    )
      throw new IdentityError("unauthenticated");
    return { header, claims };
  } catch {
    throw new IdentityError("unauthenticated");
  }
}
function publicJWKS(value: Record<string, unknown>): void {
  if (
    !Array.isArray(value.keys) ||
    value.keys.length < 1 ||
    value.keys.length > 32
  )
    throw new IdentityError("unavailable");
  const kids = new Set<string>();
  for (const raw of value.keys) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw))
      throw new IdentityError("unavailable");
    const key = raw as Record<string, unknown>;
    if (
      key.kty !== "RSA" ||
      typeof key.kid !== "string" ||
      !key.kid ||
      Buffer.byteLength(key.kid) > 128 ||
      kids.has(key.kid) ||
      (key.use !== undefined && key.use !== "sig") ||
      (key.alg !== undefined && key.alg !== "RS256") ||
      ["d", "p", "q", "dp", "dq", "qi", "oth", "k", "x5u"].some(
        (name) => name in key,
      ) ||
      (key.key_ops !== undefined &&
        (!Array.isArray(key.key_ops) ||
          key.key_ops.length !== 1 ||
          key.key_ops[0] !== "verify"))
    )
      throw new IdentityError("unavailable");
    if (
      typeof key.n !== "string" ||
      typeof key.e !== "string" ||
      decode(key.n, 1024).length < 256 ||
      decode(key.e, 8).length < 1
    )
      throw new IdentityError("unavailable");
    kids.add(key.kid);
  }
}
export class OIDCVerifier {
  readonly profile: IdentityProfile;
  readonly #vault: IdentityVault;
  readonly #network: IdentityNetwork;
  readonly #resolver: ReturnType<typeof createRemoteJWKSet>;
  constructor(
    profile: IdentityProfile,
    vault: IdentityVault,
    options: {
      testCA?: Buffer;
      testTimings?: { cooldownDuration: number; cacheMaxAge: number };
    } = {},
  ) {
    if (
      vault.reference !== profile.grantVaultReference ||
      (profile.mode === "apple-production" &&
        (vault.mode !== "production" || options.testCA || options.testTimings))
    )
      throw new IdentityError("unavailable");
    this.profile = profile;
    this.#vault = vault;
    this.#network = new IdentityNetwork(
      [profile.jwksURL, profile.tokenURL, profile.revokeURL],
      options.testCA,
    );
    const timings = options.testTimings;
    if (
      timings &&
      (!Number.isInteger(timings.cooldownDuration) ||
        timings.cooldownDuration < 1 ||
        timings.cooldownDuration > 30000 ||
        !Number.isInteger(timings.cacheMaxAge) ||
        timings.cacheMaxAge < 1 ||
        timings.cacheMaxAge > 600000)
    )
      throw new IdentityError("unavailable");
    this.#resolver = createRemoteJWKSet(new URL(profile.jwksURL), {
      timeoutDuration: 3000,
      cooldownDuration: timings?.cooldownDuration ?? 30000,
      cacheMaxAge: timings?.cacheMaxAge ?? 600000,
      [customFetch]: async (input, init) => {
        if (String(input) !== profile.jwksURL)
          throw new IdentityError("unavailable");
        const response = await this.#network.fetch(profile.jwksURL, {
          timeout: 3000,
          maximumBytes: 65536,
          ...(init?.signal ? { signal: init.signal } : {}),
        });
        const text = await response.text();
        let keys: Record<string, unknown>;
        try {
          keys = parseJSON(text, { maximumDepth: 8, maximumNodes: 512 });
          publicJWKS(keys);
        } catch {
          throw new IdentityError("unavailable");
        }
        return new Response(JSON.stringify(keys), {
          status: 200,
          headers: { "content-type": "application/json" },
        });
      },
    });
  }
  async #token(
    token: string,
    context?: ChallengeProofContext,
    nonceRequired = true,
  ): Promise<JWTPayload> {
    const inspected = inspectCompactToken(token);
    try {
      const { payload } = await jwtVerify(token, this.#resolver, {
        issuer: this.profile.issuer,
        audience: this.profile.audience,
        algorithms: ["RS256"],
        requiredClaims: [
          "iss",
          "sub",
          "aud",
          "exp",
          "iat",
          ...(nonceRequired ? ["nonce"] : []),
        ],
        clockTolerance: 60,
        maxTokenAge: "5m",
      });
      if (
        payload.iss !== this.profile.issuer ||
        payload.aud !== this.profile.audience ||
        typeof payload.sub !== "string" ||
        !payload.sub ||
        Buffer.byteLength(payload.sub) > 256 ||
        /[\u0000-\u001f\u007f]/.test(payload.sub) ||
        !Number.isSafeInteger(payload.iat) ||
        !Number.isSafeInteger(payload.exp) ||
        payload.exp! <= payload.iat! ||
        payload.exp! <= Date.now() / 1000 ||
        payload.iat! > Date.now() / 1000 + 60 ||
        (context && payload.iat! < context.createdAt.getTime() / 1000 - 60)
      )
        throw new IdentityError("unauthenticated");
      if (context && (nonceRequired || payload.nonce !== undefined)) {
        if (
          typeof payload.nonce !== "string" ||
          !payload.nonce ||
          !timingSafeEqual(
            createHash("sha256").update(payload.nonce).digest(),
            context.nonceDigest,
          )
        )
          throw new IdentityError("unauthenticated");
      }
      if (inspected.claims.aud !== payload.aud)
        throw new IdentityError("unauthenticated");
      return payload;
    } catch {
      throw new IdentityError("unauthenticated");
    }
  }
  async verifyAndRedeem(
    context: ChallengeProofContext,
    nativeToken: string,
    authorizationCode: string,
    signal: AbortSignal,
  ): Promise<VerifiedIdentity> {
    if (
      !authorizationCode ||
      Buffer.byteLength(authorizationCode) > 4096 ||
      signal.aborted
    )
      throw new IdentityError("invalid");
    const native = await this.#token(nativeToken, context, true);
    const secret = await this.#vault.signClientSecret(this.profile, signal);
    const form = new URLSearchParams({
      grant_type: "authorization_code",
      code: authorizationCode,
      client_id: this.profile.audience,
      client_secret: secret,
    }).toString();
    const response = await this.#network.fetch(this.profile.tokenURL, {
      method: "POST",
      body: form,
      signal,
      timeout: 5000,
      maximumBytes: 32768,
    });
    let grant: Record<string, unknown>;
    try {
      grant = parseJSON(await response.text(), {
        maximumDepth: 8,
        maximumNodes: 32,
      });
    } catch {
      throw new IdentityError("unavailable");
    }
    if (
      typeof grant.id_token !== "string" ||
      typeof grant.access_token !== "string" ||
      !grant.access_token ||
      Buffer.byteLength(grant.access_token) > 8192 ||
      typeof grant.refresh_token !== "string" ||
      !grant.refresh_token ||
      Buffer.byteLength(grant.refresh_token) > 8192 ||
      typeof grant.token_type !== "string" ||
      grant.token_type.toLowerCase() !== "bearer" ||
      !Number.isSafeInteger(grant.expires_in) ||
      Number(grant.expires_in) < 1 ||
      Number(grant.expires_in) > 86400
    )
      throw new IdentityError("unauthenticated");
    const exchanged = await this.#token(grant.id_token, context, false);
    if (
      native.sub !== exchanged.sub ||
      native.iss !== exchanged.iss ||
      native.aud !== exchanged.aud ||
      signal.aborted
    )
      throw new IdentityError("unauthenticated");
    const proof = Object.freeze({
      [brand]: true as const,
      profileID: this.profile.profileID,
      issuer: this.profile.issuer,
      subject: native.sub!,
      audience: this.profile.audience,
      challengeID: context.challengeID,
      attemptID: context.attemptID,
      refreshToken: grant.refresh_token,
      identityDigest: createHash("sha256")
        .update(
          JSON.stringify([
            this.profile.issuer,
            native.sub,
            this.profile.audience,
          ]),
        )
        .digest("hex"),
    });
    proofs.add(proof);
    return proof;
  }
  async verifyEvent(token: string): Promise<VerifiedIdentityEvent> {
    inspectCompactToken(token);
    try {
      const { payload } = await jwtVerify(token, this.#resolver, {
        issuer: this.profile.issuer,
        audience: this.profile.notificationAudience,
        algorithms: ["RS256"],
        requiredClaims: ["iss", "aud", "iat"],
        clockTolerance: 60,
        maxTokenAge: "24h",
      });
      const now = Date.now() / 1000;
      if (
        payload.aud !== this.profile.notificationAudience ||
        !Number.isSafeInteger(payload.iat) ||
        payload.iat! > now + 60 ||
        payload.iat! < now - 86400 ||
        (payload.exp !== undefined &&
          (!Number.isSafeInteger(payload.exp) ||
            payload.exp <= now ||
            payload.exp <= payload.iat!)) ||
        typeof payload.events !== "string" ||
        Buffer.byteLength(payload.events) > 8192
      )
        throw new IdentityError("unauthenticated");
      const body = parseJSON(payload.events, {
        maximumDepth: 8,
        maximumNodes: 32,
      });
      if (
        typeof body.sub !== "string" ||
        !body.sub ||
        Buffer.byteLength(body.sub) > 256 ||
        /[\u0000-\u001f\u007f]/.test(body.sub) ||
        !Number.isSafeInteger(body.event_time) ||
        Number(body.event_time) > now + 60 ||
        Number(body.event_time) < now - 86400
      )
        throw new IdentityError("unauthenticated");
      const kind =
        body.type === "account-deleted" ? "account-delete" : body.type;
      if (
        ![
          "consent-revoked",
          "account-delete",
          "email-enabled",
          "email-disabled",
        ].includes(String(kind))
      )
        throw new IdentityError("unauthenticated");
      if (
        payload.jti !== undefined &&
        (typeof payload.jti !== "string" ||
          !payload.jti ||
          Buffer.byteLength(payload.jti) > 128)
      )
        throw new IdentityError("unauthenticated");
      const proof = Object.freeze({
        [eventBrand]: true as const,
        profileID: this.profile.profileID,
        issuer: this.profile.issuer,
        subject: body.sub,
        tokenDigest: createHash("sha256").update(token).digest("hex"),
        ...(payload.jti ? { jti: payload.jti } : {}),
        kind: kind as VerifiedIdentityEvent["kind"],
      });
      events.add(proof);
      return proof;
    } catch {
      throw new IdentityError("unauthenticated");
    }
  }
  async revoke(refreshToken: string, signal: AbortSignal): Promise<void> {
    if (!refreshToken || Buffer.byteLength(refreshToken) > 8192)
      throw new IdentityError("unavailable");
    const secret = await this.#vault.signClientSecret(this.profile, signal);
    const form = new URLSearchParams({
      client_id: this.profile.audience,
      client_secret: secret,
      token: refreshToken,
      token_type_hint: "refresh_token",
    }).toString();
    await this.#network.fetch(this.profile.revokeURL, {
      method: "POST",
      body: form,
      signal,
      timeout: 5000,
      maximumBytes: 32768,
    });
  }
}
