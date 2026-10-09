# Independent workflow persistence fix review

Verdict: **PASS for the reviewed R15 blockers/fixes**, with native workflow QA and fresh aggregate SDK/test gates remaining.

## B1 closed: reference insertion

onPageReference now calls the same prepareNavigation helper before opening the picker. It finishes the actual token successfully, clears it only after success, then verifies/persists the current draft. The picker opens only when both steps succeed. New atomic insertReference therefore no longer knowingly runs against the active editor journal. Failure does not open/dismiss/navigate the editor.

## B2 closed: tokenless unsaved draft

persistBeforeNavigation no longer equates nil token with saved state. It checks exact Markdown/title/tag/rule/prompt bytes, purpose, IDs/hierarchy, favorite/trash/goal/attachments and optional block-ID draft against the store snapshot. Missing source changes use actual facade persistence; optional block drafts travel through block-aware journaling. Failed persistence returns false. UI prepare refreshes the page only on success. preserveConflictedDraft now requires both equal revision and equal semantic draft before skipping recovery, so same-revision differing source can be archived.

Two actual-facade disk-failure tests use the production WritingLibrary source in a Foundation-only SwiftPM target: file collision at edits forces initial journal failure, then atomic fallback is verified from decoded library.json; additional directory collision at library.json forces navigation failure and exact same-revision draft recovery, with original snapshot unchanged. The green log confirms both pass. These tests address the concrete earlier mechanism and do not mirror a fake persistence implementation.

## Boundaries/lifecycle

WritingLibrary remains MainActor/Observable and all facade/store mutations are synchronous under that isolation. Root/support/preferences injection defaults preserve production locations; tests pass distinct temporary roots and suites. Extracted SharedMarkdown/document-error/recovery type aliases are Foundation data definitions used by both actual App and package target; no duplicate model or alternate persistence path introduced. Core.hasActiveEdits is read-only and exposes no edit mutation authority. Navigation history commit still follows successful resolution/prepare and remains unchanged on false; owned private-library cross-Space scope remains explicit, without new shared-server authorization claims.

The helper clears a successfully finished token before later fallback work, which avoids reusing a finalized token if subsequent persistence fails. Partial facade metadata operations may persist some changes before a later failure, but navigation stays blocked and draft equality/recovery prevents silent success or draft discard. No additional reproducible blocking defect identified in these fixes. Native reference insertion after typing, back/forward, heading jumps, template/material interaction and final aggregate SDK checks still need their own evidence.

No sources edited or Xcode/device actions performed during this review.
