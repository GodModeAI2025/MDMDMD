# Actual UIKit broker checkpoint — iOS27 simulator

Scoped result: controlled anchor/cancellation lifecycle verified with unchanged production broker. **No live Apple authorization success.** Monotonic timer-expiry callback remains an explicit verification gap.

Isolated work/WorkspaceAppleBrokerHarness Xcode app compiles production Sources/SkriptumAuth/WorkspaceAppleAuthorization.swift and the WorkspaceClient source directory by direct paths, with no source copies/testing API added to production. Synthetic internal challenge constructed only in same-compilation harness. Bundle test.scriptum.workspace.AppleBrokerHarness, no Sign in with Apple capability/entitlements, no signing/profile/portal changes. Persistent Xcode MCP bridge built/installed on owned Skriptum iPhone QA simulator3E6A5B15-D4EC-4B7C-B435-F26DED33B8DF, iOS27.0. Actual UIKit UIWindowScene and ASAuthorizationController calls; this is more than pure gate tests, less than eligible physical-device login.

Production broker SHAbe4e648be18a3d2416ab08b81613c291dafb489e1bed8089ef531d39bf5fd002 unchanged before/after. Exact compiled production/harness hashes in built-source-hashes.json. Client owner released production freeze only after final installed binary hashes captured; later client session-validation correction is not exercised/certified by this binary. Public challenge/proof API stable, broker input uses ContinuousClock deadline.

| Controlled runtime check | Observed |
|---|---|
| Presentation anchor returns own actual UIWindow | PASS exact identity, actual UIWindowScene |
| Detached UIKit window | unavailable before request |
| Continuous deadline already expired; wall expiry+24h | expired |
| Actual pending request + second request + repeated cancel | busy, cancelled, completion1 |
| Unrelated scene notification then own scene notification twice | unrelated remainsbusy; own cancelled; completion2 total |
| Old attempt cancellation queued after new request starts | new request remainsbusy; explicit new cancel returnscancelled |
| Short20ms deadline | unentitledsystemerror unavailable before timer |
| Short500us deadline with positive lifetime/pending busy | initial-positive=true, pending=busy, completion=unavailable; timerexpiry NOT proved |

The application remained Running, pid67688 on final capture; no crash or duplicate-continuation failure. Initial pid66580 belongs to prior20ms harness build. Screenshot/hierarchy show readable nonoverlapping output and reachable control; tapped observedAX hitpoint201,100 only. No account/consent selected, no identity proof/token logged, no enrollment/Keychain operation performed. ownscene disconnect notification is deliberately posted with real scene object; it is not actual process/scene destruction proof. Framework unentitled error is a controlled expected failure, never positive authentication proof.

Evidence: before.png/hierarchy; first-controlled-run.png/hierarchy/sanitized.log; final-controlled-run.png/hierarchy/sanitized.log; built-source-hashes.json. Sanitized logs contain only BROKER_PROBE enum/outcome statements. Work-only harness includes exact deterministic runner. No production source, App signing, capabilities, server, credential, account or portal mutation.

Cleanup confirmed: StopProject stopped own pid67688; DeviceInteractionEndSession stopped Workspace Apple Broker Proof Final; XcodeCloseWorkspace closed only harness workspace-mGPa6HG6u2; persistent bridge terminated. Initial expired preparation session did not support install and was replaced with unique final identifier; no parent native session touched.

Open: actual entitlement/provisioned Apple challenge/nonce/state/credential flow on eligible physical device, user authorization and success proof; actual scene teardown, monotonic expiry callback while eligible authorization stays pending, lifecycle/deallocation under live Apple UI; real account/server/Keychain/native Scriptum integration and full product/release gates. No whole cloud/native acceptance claim.
