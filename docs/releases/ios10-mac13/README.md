# iCloud correction: iOS 1.0.1 (10), native Mac 1.0.1 (13)

Both platforms were archived from clean commit `4f1b4c5ad99e4c01c1d204889cc09de90a1faa58`. Apple confirmed successful uploads at 07:07 CEST on 15 October 2026. After owner browser sign-in, processing completion and export compliance were confirmed. **iOS 1.0.1 (10) and native macOS 1.0.1 (13) are both Im Test in Mark – Intern.** Screenshots preserve the actual group state.

The previous iOS build-9 and Mac build-10 review submissions were withdrawn to replace their builds. The new submissions are confirmed **Warten auf Prüfung**:

- iOS build 10: `40c06973-1467-41fe-b6ff-f4c45f59f552`, submitted 07:28 CEST.
- Native Mac build 13: `794a5772-a49c-450e-ac2e-f36b25e8efbf`, submitted 07:33 CEST.

Automatic release after approval remains selected on both platforms. Neither approval nor publication has occurred in the observed state. `ios10-app-review.png/.txt`, `mac13-app-review.png/.txt` and `STATE.json` record the actual build/status/IDs. The new build-9 TestFlight feedback was opened and its full original image read; it is [documented separately](../../qa-icloud-account-20261015/REPORT.md) from the later direct account-error screenshot. No claim is made that the reporter's account problem is fixed.

## Changes and evidence

- On iPhone, opening Spaces now starts at the page list. Library cloud toolbar and page Mehr → iCloud-Synchronisation open the actual settings. The accepted single-action launch and both routes were checked with Xcode MCP on an iPhone 17e simulator. [UI evidence and rejected intermediate layouts](../../qa-icloud-entry-20261015/REPORT.md).
- Durable transport files accommodate Base64 overhead for supported sync checkpoints. Journal transitions and exact-revision receipts are batched without acknowledging newer edits or losing a queue on failed writes. Two capacity failures were reproduced before correction. A real native Mac Production test with 90 historical revisions completed ready with no pending changes or error. [Manuscript tests and limits](../../qa-icloud-manuscript-20261015/REPORT.md).
- Earlier source changes since the previous uploads include Mac workflows, tasks, editor isolation, bounded diagnostic sharing and PCC scheduling policy. The native grammar-engine candidate remains excluded; no successful live scheduled PCC inference is claimed. See the separate checkpoints in [release status](../../RELEASE_STATUS.md).

## Validation and provenance

The affected model suites pass 128 tests. The full root suite passes 803 actually executed tests, with four optional tests skipped. Both final Xcode MCP app builds succeed. The actual exported iOS app passes all **25** distribution checks; the app extracted from the Mac installer passes all **28**, including native platform, sandbox, CloudKit Production, exact container, push, PCC and Store-signature gates. All 13 verifier unit tests pass. The Mac installer signature was also checked. `SOURCE.json`, package hashes, distribution proofs and upload receipts are retained here. Archives, exports, complete build/upload logs and failed-attempt logs remain under local `work/release-ios10-mac13` outside the repository.

An additional global warnings-as-errors archive attempt conflicted with dependencies' suppress-warnings setting. The retained successful archives use unchanged project compiler settings. iOS still reports two UIKit closure-conversion warnings in `FocusRestoringTextView`; both platforms report skipped App Intents metadata extraction. No zero-warning or strict-archive claim is made. An initial iOS validation used the wrong application filename; the final proof discovers and checks the actual exported `Skriptum.app` and passes. No product source was changed by those command corrections.

The export packages were checked before uploading from the same unchanged archives. Xcode's upload action exports and signs again; the recorded hashes identify the locally verified export packages, not a claim of byte identity with Apple's uploaded payload. Source and platform/build identity match the upload receipts.

The user's actual iPhone sync, a two-device manuscript transfer and CKShare collaboration are not proven by this checkpoint. Additional physical-device tests are not restored as mandatory release gates. Normal Mac Debug signing was rebuilt after the isolated Production QA override; that override is absent. No own synchronization service, CI workflow, personal manuscript transmission or CloudKit schema reset was introduced.

## Suggested internal test notes

**Deutsch:** Der Einstieg in Spaces zeigt jetzt zuerst die Seitenübersicht. Über das Wolkensymbol und im Text über „Mehr → iCloud-Synchronisation“ sind die iCloud-Einstellungen direkt erreichbar. Die Synchronisation umfangreicher Fassungshistorien und die Fehlerdiagnose wurden verbessert.

**English:** Opening Spaces now starts with the page list. iCloud settings are directly available from the cloud toolbar button and from More → iCloud Synchronisation while editing. Synchronisation of extensive revision histories and error diagnostics have been improved.

`SUBMISSION_TEXTS.json` retains the concrete submission texts. English review notes were saved for both platforms and the German iOS What’s New text was updated. The Mac initial-version page has no What’s New field, so that prepared text was not entered. No new store localization was added; the prepared English release notes remain local. Build-group assignment was completed through the existing internal group; no separate email or tester message was sent.
