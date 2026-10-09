# Owned production-adapter bridge verification

This verifies the integrated native picker adapter chain: real admission/Keychain context, actual production identity driver, signed owned issuer, real service, runtime, registry and owned binding repository. It is separate from production Apple, hosting and device acceptance.

## Evidence gap

The existing signed service probe uses loopback HTTP, while app deployment/account/binding types correctly require HTTPS. Production transport preserves platform TLS trust. The local signed issuer fixture owns a private certificate; that certificate is not in platform trust. Do not relax the deployment scheme, relabel HTTP replies as HTTPS, install a global certificate, disable TLS, swizzle Foundation or pretend a mock identity driver proves the production chain.

An isolated work-only capability probe established that registering a URLProtocol does not intercept the existing ephemeral session in this environment. That route is unavailable, and synthetic-response success was not claimed.

## Proposed narrow test seams

1. Add an instance-scoped verification TLS anchor to the identity client's request transport, available only under `DEBUG && SWIFT_PACKAGE`. Shipping initializers and normal platform trust stay unchanged. The anchor is loaded from an explicitly supplied private owned certificate. It applies only to an exact HTTPS loopback origin and server-trust challenge; verify hostname and certificate chain against that sole anchor using Security APIs. Other hosts, HTTP credential challenges and redirects remain denied/default according to existing rules. No global trust state.
2. A `DEBUG && SWIFT_PACKAGE` internal coordinator factory constructs the same private production identity driver with that actual SDK client. Verify exact origin/profile/consent and retain existing real admission, proof acquisition, cancellation and deletion semantics. It cannot accept arbitrary verified-session DTOs or mock discovery drivers.
3. The runtime's existing internal verification initializer may accept the exact registry used by that configured coordinator, so account invalidation and picker handles share one registry. Existing shipping composition continues to instantiate the real objects itself. No fake configured app state is added.
4. Own an HTTPS gateway relay/certificate and an actual signed issuer/JWKS/exchange fixture in a private process. Keep the logical and actual request origin identical. Archive the service by immutable commit, verify file digests and pinned dependency versions; do not run mutable service source.

## Required tests and assertions

- Reject wrong origin/host/anchor, untrusted certificate, redirects, malformed/oversized metadata, missing explicit fixture configuration and a shipping/default transport that cannot trust the owned self-signed certificate. First capture genuine failure at the default trust boundary.
- Actual owner enrollment saves its credential through the real admission store; no synthetic DTO substitutes for server verification. Restored sessions adopt their exact actual ticket.
- Actual list → selected UUID → fresh metadata → gated repository CAS succeeds with expected exact locator/origin/profile/account. Local document bytes/revisions remain unchanged.
- Readback revoked/denied before commit never persists. Gate denial-first and commit-first orders remain covered by existing tests; strengthen the bridge with actual credential removal/marker persistence where the host permits real isolated Keychain access.
- Old consumer/facade/account callbacks cannot mutate a replacement binding. Logout fences further metadata reads and account B remains usable. Cold restart loads the real binding only after matching actual account restoration.
- Cleanup only owned credentials, temporary keys/certificates, schema, sessions and processes; retain the parent verification PostgreSQL instance. Print counts/redacted diagnostics, never tokens, private URLs, grants or certificate keys.

## Scope and validation

Production files affected only if required: `BoundedTransport.swift`, `WorkspaceIdentityClient.swift`, `WorkspaceAccountCoordinator.swift`, `WorkspaceAccountRuntime.swift`, with all verification entry points compile-gated. Permanent tests and a private fixture runner/probe establish actual behavior. Review/audit every seam before calling it accepted; root/module/SDK checks run once after source freeze. Native QA runs against unchanged shipping sources and its mock layout evidence cannot establish this bridge.

The test-only seam does not prove platform-trusted production HTTPS, real Apple UI, commercial OAuth, PCC, installed devices or updated TestFlight. Those remain in the original objective. If the host denies isolated Keychain access, retain the actual failure and continue available work rather than substituting fake Security as real proof.
