export class IdentityError extends Error {
  readonly code:
    "invalid" | "unauthenticated" | "unavailable" | "limited" | "deleted";
  constructor(code: IdentityError["code"]) {
    super(code);
    this.code = code;
  }
}
export interface IdentityProfile {
  readonly profileID: string;
  readonly consentVersion: string;
  readonly issuer: string;
  readonly audience: string;
  readonly notificationAudience: string;
  readonly jwksURL: string;
  readonly tokenURL: string;
  readonly revokeURL: string;
  readonly teamID: string;
  readonly keyID: string;
  readonly signingVaultReference: string;
  readonly grantVaultReference: string;
  readonly mode: "apple-production" | "owned-test";
}
export interface IdentityConfiguration extends Partial<IdentityProfile> {
  enabled: boolean;
}
export function identityProfile(
  configuration: IdentityConfiguration,
): Readonly<IdentityProfile> | undefined {
  if (!configuration.enabled) return undefined;
  const fields = [
    "profileID",
    "consentVersion",
    "issuer",
    "audience",
    "notificationAudience",
    "jwksURL",
    "tokenURL",
    "revokeURL",
    "teamID",
    "keyID",
    "signingVaultReference",
    "grantVaultReference",
  ] as const;
  for (const field of fields) {
    const value = configuration[field];
    if (
      typeof value !== "string" ||
      !value ||
      Buffer.byteLength(value) > 256 ||
      value.trim() !== value ||
      /[\u0000-\u0020\u007f]/.test(value)
    )
      throw new IdentityError("unavailable");
  }
  if (
    !/^[A-Za-z0-9._-]{1,128}$/.test(configuration.profileID!) ||
    !/^[A-Za-z0-9._-]{1,128}$/.test(configuration.consentVersion!)
  )
    throw new IdentityError("unavailable");
  const mode = configuration.mode ?? "apple-production";
  if (!["apple-production", "owned-test"].includes(mode))
    throw new IdentityError("unavailable");
  for (const field of ["issuer", "jwksURL", "tokenURL", "revokeURL"] as const) {
    let url: URL;
    try {
      url = new URL(configuration[field]!);
    } catch {
      throw new IdentityError("unavailable");
    }
    if (
      url.protocol !== "https:" ||
      url.username ||
      url.password ||
      url.search ||
      url.hash
    )
      throw new IdentityError("unavailable");
    if (
      mode === "apple-production" &&
      (url.hostname !== "appleid.apple.com" || (url.port && url.port !== "443"))
    )
      throw new IdentityError("unavailable");
    if (
      mode === "owned-test" &&
      !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)
    )
      throw new IdentityError("unavailable");
  }
  if (
    mode === "apple-production" &&
    (!/^[A-Z0-9]{10}$/.test(configuration.teamID!) ||
      !/^[A-Z0-9]{10}$/.test(configuration.keyID!))
  )
    throw new IdentityError("unavailable");
  if (
    mode === "apple-production" &&
    (configuration.issuer !== "https://appleid.apple.com" ||
      configuration.jwksURL !== "https://appleid.apple.com/auth/keys" ||
      configuration.tokenURL !== "https://appleid.apple.com/auth/token" ||
      configuration.revokeURL !== "https://appleid.apple.com/auth/revoke")
  )
    throw new IdentityError("unavailable");
  return Object.freeze(
    Object.fromEntries([
      ...fields.map((field) => [field, configuration[field]]),
      ["mode", mode],
    ]) as unknown as IdentityProfile,
  );
}

export function identityFromEnvironment(
  environment: NodeJS.ProcessEnv,
): IdentityProfile | undefined {
  if (
    environment.SCRIPTUM_IDENTITY_MODE &&
    environment.SCRIPTUM_IDENTITY_MODE !== "apple-production"
  )
    throw new IdentityError("unavailable");
  const enabled = environment.SCRIPTUM_IDENTITY_ENABLED;
  if (enabled !== undefined && enabled !== "true" && enabled !== "false")
    throw new IdentityError("unavailable");
  if (enabled !== "true") return undefined;
  if (environment.SCRIPTUM_OIDC_ALLOWED_ALGORITHMS !== "RS256")
    throw new IdentityError("unavailable");
  return identityProfile({
    enabled: true,
    mode: "apple-production",
    profileID: environment.SCRIPTUM_IDENTITY_PROFILE_ID,
    consentVersion: environment.SCRIPTUM_IDENTITY_CONSENT_VERSION,
    issuer: environment.SCRIPTUM_OIDC_ISSUER,
    audience: environment.SCRIPTUM_OIDC_AUDIENCE,
    notificationAudience: environment.SCRIPTUM_APPLE_NOTIFICATION_AUDIENCE,
    jwksURL: environment.SCRIPTUM_OIDC_JWKS_URL,
    tokenURL: environment.SCRIPTUM_OIDC_TOKEN_URL,
    revokeURL: environment.SCRIPTUM_OIDC_REVOKE_URL,
    teamID: environment.SCRIPTUM_APPLE_TEAM_ID,
    keyID: environment.SCRIPTUM_APPLE_KEY_ID,
    signingVaultReference:
      environment.SCRIPTUM_APPLE_PRIVATE_KEY_VAULT_REFERENCE,
    grantVaultReference: environment.SCRIPTUM_IDENTITY_GRANT_VAULT_REFERENCE,
  });
}
