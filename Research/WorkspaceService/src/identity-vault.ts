import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import { constants } from "node:fs";
import { mkdir, open, rename, unlink, lstat } from "node:fs/promises";
import { join, resolve } from "node:path";
import { IdentityError } from "./identity-config.ts";
import type { IdentityProfile } from "./identity-config.ts";

export interface RetainedGrant {
  profileID: string;
  identityDigest: string;
  refreshToken: string;
}
export interface IdentityVault {
  readonly mode: "production" | "owned-test";
  readonly reference: string;
  signClientSecret(
    profile: IdentityProfile,
    signal: AbortSignal,
  ): Promise<string>;
  retain(
    reference: string,
    grant: RetainedGrant,
    signal: AbortSignal,
  ): Promise<void>;
  load(reference: string, signal: AbortSignal): Promise<RetainedGrant>;
  remove(reference: string, signal: AbortSignal): Promise<void>;
}
/** Real authenticated encryption for owned verification fixtures only, never a production fallback. */
export class EncryptedFileIdentityVault implements IdentityVault {
  readonly mode = "owned-test" as const;
  readonly reference: string;
  readonly #root: string;
  readonly #key: Buffer;
  readonly #signer: (
    profile: IdentityProfile,
    signal: AbortSignal,
  ) => Promise<string>;
  constructor(options: {
    root: string;
    encryptionKey: Buffer;
    reference: string;
    signer: (profile: IdentityProfile, signal: AbortSignal) => Promise<string>;
  }) {
    if (
      !Buffer.isBuffer(options.encryptionKey) ||
      options.encryptionKey.length !== 32 ||
      !options.reference
    )
      throw new IdentityError("unavailable");
    this.#root = resolve(options.root);
    this.#key = Buffer.from(options.encryptionKey);
    this.reference = options.reference;
    this.#signer = options.signer;
  }
  async signClientSecret(
    profile: IdentityProfile,
    signal: AbortSignal,
  ): Promise<string> {
    if (profile.mode !== "owned-test" || signal.aborted)
      throw new IdentityError("unavailable");
    return this.#signer(profile, signal);
  }
  #path(reference: string): string {
    if (!/^grant:[0-9a-f-]{36}$/.test(reference))
      throw new IdentityError("unavailable");
    return join(this.#root, reference.slice(6) + ".vault");
  }
  async #directory(): Promise<void> {
    await mkdir(this.#root, { recursive: true, mode: 0o700 });
    const info = await lstat(this.#root);
    if (
      !info.isDirectory() ||
      info.isSymbolicLink() ||
      (info.mode & 0o077) !== 0
    )
      throw new IdentityError("unavailable");
  }
  async retain(
    reference: string,
    grant: RetainedGrant,
    signal: AbortSignal,
  ): Promise<void> {
    if (
      signal.aborted ||
      !grant.refreshToken ||
      Buffer.byteLength(grant.refreshToken) > 8192 ||
      grant.identityDigest.length !== 64
    )
      throw new IdentityError("unavailable");
    await this.#directory();
    const destination = this.#path(reference),
      temporary = destination + ".pending-" + randomBytes(16).toString("hex");
    const nonce = randomBytes(12),
      cipher = createCipheriv("aes-256-gcm", this.#key, nonce);
    cipher.setAAD(Buffer.from(reference));
    const ciphertext = Buffer.concat([
      cipher.update(JSON.stringify(grant), "utf8"),
      cipher.final(),
    ]);
    const payload = Buffer.concat([
      Buffer.from("SIV1"),
      nonce,
      cipher.getAuthTag(),
      ciphertext,
    ]);
    const file = await open(
      temporary,
      constants.O_WRONLY |
        constants.O_CREAT |
        constants.O_EXCL |
        constants.O_NOFOLLOW,
      0o600,
    );
    try {
      await file.writeFile(payload);
      await file.sync();
      await file.close();
      if (signal.aborted) throw new IdentityError("unavailable");
      await rename(temporary, destination);
    } catch {
      await file.close().catch(() => undefined);
      await unlink(temporary).catch(() => undefined);
      throw new IdentityError("unavailable");
    }
  }
  async load(reference: string, signal: AbortSignal): Promise<RetainedGrant> {
    if (signal.aborted) throw new IdentityError("unavailable");
    const file = await open(
      this.#path(reference),
      constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK,
    );
    try {
      const info = await file.stat();
      if (!info.isFile() || info.size > 32768 || (info.mode & 0o077) !== 0)
        throw new IdentityError("unavailable");
      const payload = await file.readFile();
      if (
        payload.length > 32768 ||
        payload.subarray(0, 4).toString() !== "SIV1"
      )
        throw new IdentityError("unavailable");
      const decipher = createDecipheriv(
        "aes-256-gcm",
        this.#key,
        payload.subarray(4, 16),
      );
      decipher.setAAD(Buffer.from(reference));
      decipher.setAuthTag(payload.subarray(16, 32));
      const value = JSON.parse(
        Buffer.concat([
          decipher.update(payload.subarray(32)),
          decipher.final(),
        ]).toString("utf8"),
      ) as RetainedGrant;
      if (
        !value.refreshToken ||
        Buffer.byteLength(value.refreshToken) > 8192 ||
        value.identityDigest.length !== 64 ||
        signal.aborted
      )
        throw new IdentityError("unavailable");
      return value;
    } catch {
      throw new IdentityError("unavailable");
    } finally {
      await file.close();
    }
  }
  async remove(reference: string, signal: AbortSignal): Promise<void> {
    if (signal.aborted) throw new IdentityError("unavailable");
    await unlink(this.#path(reference)).catch((error) => {
      if ((error as { code?: string }).code !== "ENOENT")
        throw new IdentityError("unavailable");
    });
  }
}
