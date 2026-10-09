/** Fail closed before connecting/migrating/cleaning any verification resources. */
export function verificationURL(
  value: string | undefined,
  optIn: string | undefined,
): string {
  if (!value || optIn !== "YES")
    throw new Error(
      "Dedicated PostgreSQL verification URL and explicit opt-in required",
    );
  const parsed = new URL(value);
  if (
    !["postgres:", "postgresql:"].includes(parsed.protocol) ||
    !["127.0.0.1", "localhost", "[::1]"].includes(parsed.hostname)
  )
    throw new Error("Verification database must use loopback");
  return value;
}
