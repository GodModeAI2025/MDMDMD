# SkriptumWorkspaceClient

Standalone Foundation Swift module for the current Workspace HTTP gateway. See [the client plan](../../docs/WORKSPACE_CLIENT_PLAN.md) for wire contract, actual cross-language evidence and remaining integration gates.

Production configuration requires an explicit HTTPS origin and an opaque Workspace session bound to that exact origin/account. There is no default endpoint, login/dev-token fallback, provider credential upload, plaintext source write or implementation of the future identity API. `loopbackForTesting` is an explicit verification-only constructor.

The complete test suite intentionally requires `SCRIPTUM_CLIENT_VERIFICATION_FIXTURE` pointing to the mode0600 file supplied by the owned real HTTP/PostgreSQL runner. Without it, the integration test fails rather than skipping. Unit-only runs can select the four named contract tests and must be reported as unit evidence only. No database URL or session token belongs in logs or command arguments.

Root native app/Keychain wiring has not been performed. Logout removes local actor admission immediately; the integrating credential store must separately erase persisted credentials and distinguish confirmed remote revocation from unknown outcome.

Permanent real HTTP/PG fixture (from repository root):

```sh
SCRIPTUM_ALLOW_VERIFICATION_SCHEMA=YES SCRIPTUM_CLIENT_VERIFICATION_PG_CONFIG=/absolute/path/to/private-verification-config.json node Modules/SkriptumWorkspaceClient/Verification/run.ts
```

The private mode0600 JSON config supplies a `url` for the explicitly owned loopback PostgreSQL18 verification database. The runner never prints it or session tokens. Installed server `pg`8.23.1 dependencies must already be available; it does not install dependencies or modify backend sources. It archives exact gateway commit78f879f and verifies its tree/hash, creates an isolated owned schema under advisory lock, and removes only that schema and its own temporary snapshot/private fixture on completion. A missing config/opt-in, wrong PG version or failed test is a failure, never a skip.
