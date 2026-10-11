export class WorkspaceError extends Error {
  readonly code:
    "invalid" | "unauthenticated" | "forbidden" | "missing" | "conflict";
  constructor(code: WorkspaceError["code"]) {
    super(code);
    this.code = code;
  }
}
export type RoleRank = 0 | 1 | 2 | 3;
export function parseUUID(value: string): string {
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      value,
    )
  )
    throw new WorkspaceError("invalid");
  return value.toLowerCase();
}
export function effectiveRole(
  parent: RoleRank,
  override: RoleRank | undefined,
  ceiling: RoleRank,
): RoleRank {
  for (const value of [parent, override, ceiling])
    if (
      value !== undefined &&
      (!Number.isInteger(value) || value < 0 || value > 3)
    )
      throw new WorkspaceError("invalid");
  return Math.min(parent, override ?? parent, ceiling) as RoleRank;
}
export interface EncryptedEnvelope {
  ciphertext: Buffer;
  nonce: Buffer;
  digest: Buffer;
  keyReference: string;
  version: 1;
}
export function validateEnvelope(value: EncryptedEnvelope): void {
  if (
    !Buffer.isBuffer(value.ciphertext) ||
    value.ciphertext.length < 17 ||
    value.ciphertext.length > 2 * 1024 * 1024 + 16 ||
    !Buffer.isBuffer(value.nonce) ||
    value.nonce.length !== 12 ||
    !Buffer.isBuffer(value.digest) ||
    value.digest.length !== 32 ||
    typeof value.keyReference !== "string" ||
    Buffer.byteLength(value.keyReference) < 1 ||
    Buffer.byteLength(value.keyReference) > 256 ||
    value.version !== 1
  )
    throw new WorkspaceError("invalid");
}
export function boundedTitle(title: string): void {
  if (
    typeof title !== "string" ||
    Buffer.byteLength(title) < 1 ||
    Buffer.byteLength(title) > 4096
  )
    throw new WorkspaceError("invalid");
}
export function schemaIdentifier(schema: string): string {
  if (!/^[a-z][a-z0-9_]{0,62}$/.test(schema))
    throw new WorkspaceError("invalid");
  return `"${schema}"`;
}
