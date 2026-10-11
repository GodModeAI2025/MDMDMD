# Exact multi-step correction undo/redo

The former WritingQualitySheet undo retained only Markdown strings and one correction. A fixture with duplicate paragraphs/comment anchors and a structural correction reproduced changed block IDs after undo, despite identical restored text. BEFORE_TESTS.txt preserves that failure.

WritingCorrectionHistory now retains exact before/after blocks, including IDs and UTF-8 source. The quality sheet captures the actual Core page before/after an accepted correction and exposes undo plus redo. Every inverse operation checks the expected current revision and block bytes/IDs, then uses one durable setBlocks commit. Stack movement and the next expected revision occur only after success. A new correction after undo drops the redo branch; intervening external changes cannot be overwritten.

The view owns its history. Retention is bounded to 100 steps and a 32 MiB accounting budget for UTF-8 bytes plus 64 bytes per retained block; this is not a process resident-memory guarantee. Oversized entries clear the in-memory stacks without affecting durable versions. A visible limit notice directs authors to the page's version history. Closing/reopening the sheet resets its in-memory correction stack; durable versions remain independently available.

Six model regressions cover original block IDs/comment anchors, three-step Unicode/CRLF/table/image-reference undo/redo and disk reopen, branching, revision and external disk conflicts, failed redo with an active journal plus successful retry, and both history limits without deleting durable versions. Image references in synthetic source do not prove real image rendering/restoration. Final FULL_TESTS.txt and compile receipts record integration checks.

The device QA agent freshly found the old NativePickerOwnedProxy Xcode access dialog (PID24613), MCP Permission disabled and server not running. No dialog/permission/server/bridge/session/install/device action occurred. Native button layout/activation, checking state, multi-step interactions, bound notice and failure/navigation behavior remain unverified.

This improves native/rule-based quality-correction undo; it does not establish whole-editor undo/redo, AI proposal undo, every tool/media action, cross-window undo coordination, physical Files/CloudKit or current-source TestFlight. R03/R14 and the entire R01-R15 matrix remain binding and open at their full scope. No pending permission question was treated as approval.

Final integration: 580 Swift Testing headline with three optional external/native skips, all 58 XCTest passing; unsigned Debug Simulator and iOS Release builds succeed. These receipts do not establish native or release acceptance.
