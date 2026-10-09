# Library discovery contract — implementation evidence

The service now supports authenticated `GET /libraries` and `GET /libraries/<UUID>`. Root-only permission checks, eight-row pages, advancing UUID cursors, post-lock session/permission rechecks and a 256 KiB response ceiling are implemented. The Swift identity actor exposes strict typed reads and fences replies after logout or admission replacement. Existing identity parsing keeps array rejection; only metadata-page parsing opts into bounded arrays.

## Verified

- Seven actual current-source HTTP/PostgreSQL discovery tests passed; typecheck passed. Initial seven missing-route failures are retained in `workspace-library-discovery-red.log`. A canonical tombstone fixture correction was shown before editing; its 401 assertions and schema were preserved.
- Six focused Swift discovery tests passed, including two real owned-loopback transport cases that hold a reply until after logout. Missing-API failures were captured before implementation; frozen client assertions were not edited afterward.
- Complete service verification passed all 60 tests (53 existing plus 7 discovery), with actual PostgreSQL and owned HTTPS/issuer fixtures. The new test script is included in the existing complete runner.
- Complete Swift module verification passed all 38 tests with its required owned HTTP/PostgreSQL fixture. An earlier plain `swift test` lacked the explicit real-fixture configuration and had several startup deadline failures during concurrent service work; that failed attempt is retained. The proper isolated verification command passed without changing those assertions or deadlines.
- Complete app tests passed: 45 XCTest and 210 Swift Testing tests, 255 total. The regenerated iOS 27 app SDK build succeeded.
- Independent server and client review/audit passed; inspected hashes and boundaries are recorded in the corresponding review documents. No new dependency or schema migration was introduced.
- The signed discovery fixture passed 32 assertions (20 original identity/CAS/retention assertions plus 12 metadata assertions) against immutable service commit `b22f734c897710d5f0ffdbc72bd214fb81c17e04`, Git tree `20c99e117ce456f22cc54300a0bb9fa756842168`. Its external 43-file manifest digest is `cc62c57cba4f4683ff2d2ccdbedb56c5ade8638845c3b787cc71b45a1b467499`. Independent review recomputed the archived bytes and passed. Actual owner/viewer reads, grant/revocation, signed-out denial, a maximally escaped title above the old 24 KiB transport ceiling, and retained viewer metadata after owner tombstone are covered. Source/token/vault fixtures remain synthetic and privately owned; this is not real Apple authorization.

Logs live in the task's private `work/` directory: `workspace-discovery-client-green.log`, `workspace-library-discovery-green.log`, `workspace-discovery-service-full.log`, `workspace-discovery-module-full.log` (failed), `workspace-discovery-module-owned-full.log` (passed), `workspace-discovery-root-full.log`, and `workspace-discovery-app-sdk.log`.

## Remaining original scope

The native picker and connection readback are not implemented by this completed contract stage. They must carry actual durable admission tickets and exact window/facade generations before binding a selected library. The signed local issuer fixture proves the new wire contract separately from production Apple, operator and hosting activation.

Scoped page/space sharing, collaboration, encryption-key provisioning, deployed scheduled execution, production operator/HTTPS/vault, commercial ChatGPT access, real PCC/provider/device validation and updated TestFlight delivery remain open parts of the original requirements. Discovery DTOs are metadata, not ongoing permission authority.

## Account visual correction

The account inspector now uses the native inline title and visibly dims the same disabled Apple control. Actual Xcode MCP retesting proved the corrected light layout and maximum accessibility text, including lower controls. The original and corrected evidence is archived in `qa-workspace-account-ui/`. Corrected dark mode was not repeated; no eligible iPad simulator was available, and internal registration persistence/live cloud actions were not proven. Owned sessions/processes/workspaces were ended and simulator Settings restored.
