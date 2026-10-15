# Native Mac iCloud sharing completion retest — 15 October 2026

The corrected native share completion path passed two real UI cycles in Scriptum 1.0.1 (20): open the existing Apple sharing dialog, click **Done**, return to the document without the prior red error banner. After each cycle, the app's diagnostic reported **ready / none**, with pending, received and conflict counters all zero.

The test used the same isolated synthetic QA library as `../qa-share-dialog-mac-20261015/`. The signed app's CloudKit environment was explicitly verified as **Development** before launch. Neither the normal user library nor sharing permissions were modified; no participant was added or invited. The QA data and its existing Development share were retained.

## Evidence and revision boundaries

- `SOURCE-BEFORE.json` identifies the actual binary and source used by the UI run. `signed-entitlements.plist` and `codesign-verify.log` capture signing verification before launch.
- `running-qa-process.json` binds PID 68811 to the precise isolated QA arguments. `qa-process-exit.json` confirms regular app termination.
- `runtime-result.json` and `ui-observations-sanitized.txt` record the actual outcomes. Original screenshots and accessibility output remain in the task transcript; the text record is a sanitized transcription, not a raw image artifact.
- Both SDK builds passed after the completion fix and message-preservation change: native Mac (5.059 s) and generic iOS (6.352 s), zero reported errors. Their receipts and logs are retained here.
- During this UI run, another agent added guards against late callbacks after library/session/connection changes. `SOURCE-AFTER.json` explicitly records changed hashes for `ICloudLibrarySession.swift` and `MacPageInspector.swift`. The UI result therefore applies to the pre-guard binary in `SOURCE-BEFORE.json`, not to an unchanged final freeze.
- The final guard additions subsequently compiled successfully for native Mac through Xcode MCP (7.203 s, zero errors). `FINAL-COMPILE-SOURCE.json` binds that final SDK compile and confirms source hashes remained unchanged during it. The normal dialog loop was not redundantly repeated, per parent instruction.

Xcode was restored to **Skriptum / Any iOS Device (arm64)**, the QA process was closed, and MCP control was returned to the parent agent.

## Limits

This demonstrates native Mac presentation, ordinary Done completion, repeat opening and a healthy local iCloud diagnostic in Development. It does not demonstrate an invitation, recipient acceptance, cross-account collaboration, a production share or a newly distributed TestFlight build. The late-callback race protections have their separate automated coverage and final SDK compile, not a forced reconnect race in this UI run.
