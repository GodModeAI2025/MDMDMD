# Revised account coordinator plan review

Verdict: **PASS scoped implementation plan; all three prior blockers explicitly closed.** No implementation/runtime acceptance claim. Exact plan/current-contract review hash f38d1423446e6fe1007f6bd02536a03e7a73a58d07912973ffeaa0832d1afa65 (sorted repo-relative plan, Keychain store, identity client, cloud registry and binding repository path+NUL+bytes+NUL).

1. Shared synchronous transaction gate now owns generations/expected identities/denial state. Real Security operations must be factored into an internal synchronous primitive; admission actor cannot await old Keychain actor between check/write. MainActor marker commit uses same gate, with noawait/network/hop inside. Save linearizes at gated Security write, denial at gated durable marker commit; failure remains process-denied/unavailable.
2. Every load/save/deny/remove/clear, including stale401 callbacks, now requires generation/expected-denial/credential-session CAS. Explicit olddeny→newverifiedticket/save→oldremove and oldclear→newdeny regressions required. Stale operations mutate neither Security nor marker. Thus old cleanup cannot erase new same-scope reauthentication.
3. Account-unknown attempts own distinct provisional actors and deployment/profile cancellation is confined to those containers. Known active B slots/actors/credentials/markers in same deployment/profile remain untouched during A logout; matching regression added.

TrustedFoundation container-root canonicalization remains restricted to actual system roots and consistent library/support composition; no arbitrary path resolution/interior-link bypass. Existing weak registry is metadata-only, not a durable denial substitute. Initiating actor retains captured credential for its own revocation/deletion method, while UI/data fencing is synchronous beforeawait; remote confirmation/unknown distinct. Documents/import scopes preserved.

Implementation must prove specified interexecutor serial orders, stale destructive callbacks, failed remove/cold restart and marker corruption/capacity failures with real synchronous Security operations. No wrapper-await interpretation satisfies plan. Physical container/Keychain/Apple/provisioned deployment and account UI gates remain explicit. Read-only plan/current-contract review; no edits/tests/implementation changes or cloud PASS.

The reviewed plan subsequently received only a status-label update reflecting this verdict.
