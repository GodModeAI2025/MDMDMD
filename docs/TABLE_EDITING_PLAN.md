# R15: native table editing

This implements the existing richer-table requirement without replacing the remaining app/release scope.

Activation: a valid table block's action menu opens Tabelle bearbeiten after the current draft is durably saved. A horizontally scrollable cell grid offers inline-Markdown cell editing, body-row and column insertion/removal, explicit confirmation before removing populated content, complete-source Undo/Redo, and a raw-source preview. Unsupported/ragged/nested table syntax remains editable through the existing source editor.

Ownership: the table engine and permanent engine tests, native sheet/block action integration, and page/domain commit integration use disjoint files. Source freezes before SDK/device verification. Apple SwiftUI guidance supplies stable row/column identity and separate section views.

Persistence contract: capture library/page revision, block UUID and exact current block bytes. Each accepted cell/structure/Undo/Redo action validates its output, checks the current page revision and block bytes, replaces only that block, and atomically commits via LibraryStore.setBlocks. The callback returns success only after the commit; sheet state and history advance only then. Failed writes or stale windows retain the draft and never overwrite a newer page. Adjacent blocks and IDs remain unchanged.

Verification: table engine tests cover Unicode/CRLF/escaped pipes, rectangular syntax, explicit structural edits and last-column guards. Actual WritingLibrary tests cover disk commit/Undo, unchanged adjacent blocks/IDs, no-op revision, stale revisions, wrong source, active typing and atomic-write failure. Fresh SDK build, independent review and Xcode MCP phone/iPad interactions verify reachable native behavior; these do not establish physical-device AI/PCC or release availability.

Change log: valid pipe-less two-column tables reduced to one column receive only the required outer-pipe syntax rather than failing an otherwise valid structural action. Synthetic model fixtures use the production-owned Documents/Skriptum path required by LibraryStoragePaths validation.
