# Source-first partial draft recovery

A draft with a missing attached image previously failed before any text recovery record was published (BEFORE_TESTS.txt). The final implementation saves and verifies the entire WritingPage first, marked sourceOnly, then archives every attachment independently. Failure retains the text record and any good archived images. Repairing media completes the same ID/date; full restore still checks all resources before consuming the recovery.

Recovery scanning shows valid records even beside unreadable ones, retains unreadable files, and reports their count. Strict Core readers still reject an incomplete scan. Legacy records without the new optional completeness field retain their complete interpretation. UUID filenames and regular files/directories are checked; expected-value deletion protects stale callers from consuming a changed record. This is not distributed locking or protection against hostile filesystem races.

The recovery sheet provides incomplete-capture status, raw Markdown export, restore failure feedback and unreadable-file count. Raw Markdown preserves source bytes but does not package images. Source-only describes capture completeness; full restore validates resources even for legacy/complete records.

## Validation

- Four model regressions: missing image preserves exact source/raw export; repaired media completes the same record and restores; corrupt neighbor remains untouched; good media survives an independently failed attachment.
- Core regressions: tolerant scanning versus strict reads, same-record completeness transition, stale expected-value deletion, legacy completeness and filename/record mismatch.
- Final full suite: 567 Swift Testing headline, three optional external/native skips; 58 XCTest with zero failures. FULL_TESTS.txt retains the actual log.
- Unsigned Debug Simulator and iOS Release builds: BUILD SUCCEEDED. RELEASE_COMPILE.json records the resulting binary hash and version, with signed/uploaded false.
- PROCESS_RESULT.json: sourceOnly receipt read back before SIGKILL of this harness's own waiting child; a new process recovers the same record and exact 216011 source bytes with decomposed accents, Japanese, emoji and CRLF. No real user data or other process is involved.

Reproduce the process check from the repository root:

```sh
swift build --package-path docs/qa-partial-recovery/ProcessHelper --scratch-path /private/tmp/ScriptumPartialRecoveryProof --disable-sandbox --skip-update
SCRIPTUM_PROCESS_PROOF_BINARY=/private/tmp/ScriptumPartialRecoveryProof/debug/LibraryProcessProof python3 docs/qa-partial-recovery/process-proof.py
```

## Native/release limits

The device QA agent's fresh read found Xcode MCP permission disabled/server not running and the old access dialog still present. No dialog/permission/bridge/session/install/device action occurred. Incomplete status, raw Markdown sharing, local errors and unreadable count remain natively unverified. The process proof is macOS Core SIGKILL recovery, not physical iOS or power-loss persistence. Current-source signed archive, provisioning, iCloud collaboration, TestFlight upload and the full R01-R15 acceptance matrix remain open. Existing unanswered permission questions were not treated as approval.
