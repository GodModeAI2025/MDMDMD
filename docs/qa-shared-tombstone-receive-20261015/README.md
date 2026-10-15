# Shared iCloud deletion receive — 15 October 2026

A permanent owner deletion could block all subsequent participant refreshes. Scriptum represents logical deletions as retained `ScriptumItemV1` records with `operation=tombstone`, an empty-payload digest and no asset. The owner journal correctly sends them with their existing parent. The participant snapshot receiver nevertheless demanded `upsert` plus a payload for every descendant and threw `invalidRecord`.

The receiver now validates each tombstone's actual fetched ID/zone, unchanged parent, library, canonical kind/UUID/revision, allowed document record type, empty payload and exact empty SHA-256 before omitting the deleted page/comment/revision from its reconstructed snapshot. Root deletion still fails closed, retaining the checkpoint. Live dangling descendants still fail normal hierarchy validation. No record outside the selected shared hierarchy is fetched. Native physical deletion handling is unchanged.

The existing checkpoint revision fence, pending-edit protection, full document/attachment validation and final participant revalidation still precede replacement. No participant grant is persisted. Only the post-fetch installation routine was extracted for fixtures; production calls that same routine with CloudKit's actual per-record fetch closure. Identity/zone equality is also checked on fetched live records.

## Actual evidence

- `red.log`: initial sandbox/cache access failure; no executed regression is claimed.
- `red-test.log`: initial test-fixture compile errors (missing comment blockID and internal revision initializer); no failing behavior is inferred from those errors.
- `red-regression.log`: corrected fixture, actual unmodified receive behavior fails with `invalidRecord`.
- `green-initial.log`: identical owner-projection reproduction passes after the correction.
- `green-focused.log` / `green-final.log`: final six test definitions / 13 executed cases pass. They cover actual owner projection removing a trashed child and its comment/revision, durable reopen, Unicode/CRLF preservation, eight malformed/root-delete cases with byte-identical retained checkpoints, pending edits/queue preservation, permission revocation, mismatched fetched zone and unrelated-share isolation.
- `core-workspace-tests.log`: 281 Core and 213 WorkspaceModel test definitions pass. The final unrelated-share fixture was added afterward and passes in `green-final.log`; application code is unchanged between these runs.
- Official Xcode-MCP `BuildProject` receipts and complete logs: iOS SDK build 4.560 seconds and native Mac SDK build 4.508 seconds, both successful with no reported errors. The main workspace returns to Skriptum / Any iOS Device (arm64). No app, simulator or physical device was launched.

The Apple [record-zone changes documentation](https://developer.apple.com/documentation/cloudkit/ckdatabase/recordzonechanges(inzonewith:since:desiredkeys:resultslimit:)) distinguishes changed records from physical deletions. The logical tombstone format is Scriptum's own existing application contract, verified against `ICloudLibraryProjection` and `ICloudSyncEngine`, rather than an invented Apple deletion event.

This is a local common-code correction after the delivered iOS19/Mac20 archives. It does not itself prove live recipient invitation/acceptance or multi-account CloudKit synchronization, nor activate native grammar or change existing Store submissions. The Portal was separately reread this turn: iOS19 and Mac20 remain Im Test in Mark – Intern.
