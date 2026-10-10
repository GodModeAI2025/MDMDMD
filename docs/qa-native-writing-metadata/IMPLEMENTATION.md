# Continue native writing after a title change

2026-10-10. A real-store regression reproduced the failure before this correction: edit the one-block manuscript, finish its typing journal, rename through `processEditorNotification`, then type again. The title was saved, but the next text callback was incorrectly rejected as a foreign change. The failing regression is retained in `regression-before.log`.

The notification result now carries a private, non-Codable receipt created by its synchronous, revision-guarded mutation. It records the actual LibraryStore identity and exact Core page before and after the write. `PageBlockWritingAdmission` advances only if its previously accepted Core snapshot matches the receipt's before-image, the live page matches its after-image, and any successor typing token belongs to that page and store. Failed writes, queued notifications and intervening foreign writes cannot advance admission. Existing draft preservation and revision checks remain active.

## Verification

- 483 executed tests pass: 425 actual Swift Testing passes and 58 XCTest passes. Three optional tests were skipped. Coverage includes the reproduced title transition, intervening foreign changes, failed metadata writes, stale render callbacks and existing foreign-change guards. Full output: `full-tests.log`.
- Xcode MCP Build 588 passes with no errors.
- Optimized unsigned iOS Release 1.0.0 (3) passes. Executable SHA-256: `53d80e0140847b0200c1b2bee930a5a768c298e014cae1a2f1b5f6fea71dd785`. Existing warnings concern a Sendable closure and the deprecated iOS 27 BGTask submission API. This is not a signed archive or TestFlight delivery.
- Native replacement session 597–615 passes: type, edit the actual title field, type again, close, inspect saved data and reopen. Exact ordered suffix `FIRST-Café 🦊.SECOND-Café 🦊.` persists as 222 total UTF-8 bytes with one original block ID. The edited title persists. No false conflict or recovery prompt appeared. Initial session 589 disappeared before the rename and supplies no complete-flow proof. See `REPORT.md` and screenshots.

## Remaining scope

Own mutations committed directly by image, table, rules or history tool callbacks still need separate transaction receipts or an explicit admission handoff, with regression and native UI evidence. This change proves native typing followed by a guarded editor notification, not every tool flow or real CloudKit multi-window behavior. The iPad large-document run proves visible rendering, ordered editing and persistence; it does not establish professional latency, physical-device behavior or VoiceOver support.
