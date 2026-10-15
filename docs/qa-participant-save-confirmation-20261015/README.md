# Participant save confirmation — 15 October 2026

The participant sender acknowledged a retained page operation using only record identity and declared digest. A matching declaration with missing/different CKAsset bytes incorrectly cleared the pending page. The saved-record path likewise ignored a changed native parent in the returned receipt. These are local fault-injection regressions, not observations of an Apple server returning corrupt records.

Before acknowledgement, both paths now read the actual asset using the existing bounded no-follow reader and compare its bytes with the exact pending payload. The saved receipt must additionally preserve the expected native parent identity/action. An incomplete acknowledgement leaves the page operation and local Unicode/CRLF text intact; it does not overwrite a mismatching server payload. A retry after a simulated network failure following a successful save still acknowledges exact server data without saving that page twice. No format, schema, entitlement, migration or dependency change is introduced.

## Evidence

- `baseline.log`: the corrected four-case fixture on unchanged production source reproduces three failures (six assertions); exact retry succeeds. The earlier `invalid-parent-action-fixture.log` is retained separately: CloudKit itself rejects parent action `.deleteSelf` with an exception, so that invalid fixture was removed before the behavioral baseline. It is not counted as a product regression.
- `focused.log`: all three participant sender definitions / 21 cases pass, including existing page/Space nested edits, comments, replies, resolve/reopen and exact revision history.
- `core-workspace.log`: 296 WorkspaceModel definitions / 21 suites and 213 Core definitions / 17 suites pass; three optional definitions skip. This covers the shared store, durable queues and related owner/participant behavior at local fixture scope.
- Official Xcode MCP lists the actual workspace, then the iOS-device SDK build passes in 6.181 seconds and native Mac in 4.323 seconds, with empty reported error arrays. The original Skriptum / Any iOS Device (arm64) selection is restored. JSON responses and complete build logs are preserved here.
- `SOURCE_HASHES.json` binds the changed source and tests. Tests run via `swift test --skip-update --filter sharedSender` and `swift test --skip-update --filter 'SkriptumWorkspaceModelTests|SkriptumCoreTests'`.

## Delivery boundary

This correction is source work after internally available iOS25/Mac26. Those already-uploaded archives do not contain it. No app/device/simulator UI was launched and no live two-account collaboration is established. Native grammar distribution and broader R01–R15 requirements remain open. Existing Store submissions iOS11/Mac14 are retained.

## Subsequent internal delivery

This correction is now included in [iOS27 / native Mac28](../releases/ios27-mac28-integrity/README.md), both verified Im Test in Mark – Intern. The earlier archive boundary above remains historical. Tested source hashes match the clean delivery source. Native grammar remains excluded from ordinary Release; the own-server correction is shipped. Live two-account collaboration remains unproven; Store submissions iOS11/Mac14 are retained.
