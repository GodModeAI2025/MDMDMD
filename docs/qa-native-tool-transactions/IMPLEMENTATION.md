# Native writing across page-tool transactions

2026-10-10. Native typing previously retained an exact accepted Core snapshot. Tool callbacks replaced the UI DTO after mutating the stored page, leaving native admission on the older snapshot. The next edit could be rejected as a conflict. Title edits already carry a synchronous guarded notification receipt; this change covers the tools that mutate stored pages directly.

## Change

`PageBlockWritingAdmission.performToolMutation` checks the actual store identity and exact accepted before-image before invoking a synchronous page mutation. Each operation retains its existing revision, block/source, finding or history validation. Only a successful result with the same actual store/page and current stored revision is adopted. A failed operation, including one that changed part of the page before failing, cannot adopt authority. Foreign changes reject before the operation is called.

The actual PageWritingView passes this transaction to page rules/prompts, image import, grammar/style correction and correction Undo, history restore, table editing, page-purpose changes and reference insertion. Image loading remains asynchronous, but admission and persistence run synchronously when the data is ready. UI callbacks publish the saved result afterward.

A separate regression reproduced queued pre-tool native callbacks overwriting a saved table change. Every native block commit now requires the UUID captured by its rendering pass. A successful tool transaction replaces that UUID; a guarded editor notification replaces it only when canonical blocks change. Pure title edits preserve it. Old callbacks reject without mutating the document; new callbacks retain their original revision/store guards and typing token. No DTO or serialized provider response can supply a generation or manufacture a receipt.

## Verification

Full tests pass: 430 Swift Testing functions (including six real transaction cases for rules, table, image, history, correction and purpose) and 58 XCTest cases. Three optional tests are skipped. Tests prove stored source and block IDs, exact PNG attachment bytes, rejection before a foreign tool call, partial-failure rejection, queued pre-tool source rejection, title generation continuity and accepted new text-replacement journaling. The initial queued-callback failure is retained separately.

Xcode MCP Build 643 passes with no errors. Optimized unsigned iOS Release 1.0.0 (3) also passes. Executable SHA-256: `6a08cea92aed0038a963aea8f4cddb27e73c6d3c031ec121c99e35cd26d38bf2`. The new tool-fixture flag, composite-fixture flag and temporary-fixture identifier are absent from the executable. Existing Sendable and iOS 27 BGTask submission warnings remain. This is not a signed archive or TestFlight distribution.

The first native run confirms table → continued paragraph typing, persisted cell 12, unchanged two original block IDs and zero recoveries. The final generation-fenced run confirms table and rules persistence. After reopening and explicitly focusing the paragraph, all three suffixes persist as `FIRST-QASECOND-QATHIRD-QA`, with table 12, rules `RULE-QA`, 93 UTF-8 bytes, unchanged two original block IDs and zero recoveries. Both 314-file source manifests match before their sessions end.

**Open UI issue:** During the first attempt to type the third suffix after saving rules, the outer editor unexpectedly disappeared; that suffix did not save. No close tap preceded the disappearance. The retry proves persistence after reopen/refocus, not an uninterrupted rule-dialog → writing transition. See the final run report and `missing-third-after-dismissal.png`. Cause is not established; logs do not prove that the generation fence, nested presentation or focus handling caused it. Next work must investigate PageToolsSheet dismissal/publication and underlying native editor focus, then prove a clean uninterrupted flow. Do not mark this UI requirement complete.

## Limits

Real CloudKit sharing, physical-device/PCC/provider inference and a newly signed TestFlight upload remain separate gates. Native UI coverage must be stated per observed flow; six real-store transaction cases do not prove every native tool sheet. Partial tool failure rejection protects existing document state from later overwrite; it is not proof of atomic rollback for the legacy two-step attachment workflow. Multi-window, IME, accessibility and cross-surface Undo ordering remain additional verification work.
