# Foreground read-only rescue after journal recovery failure

BEFORE_STRICT_OPEN.txt reproduces the original failure: one corrupt neighboring JSON journal prevents opening an otherwise valid durable library. The strict initializer remains the default API and background behavior; the foreground app now explicitly requests readOnlyOnFailure.

LibraryStore loads/validates the durable library first. Recovery scans regular UUID/token-matching journal files with a 64 MiB per-file admission limit, retaining decoded changed drafts independently of failed neighbors. No recovery candidate is published and no journal removed until the entire recovery set decodes and validates. A recovery error can return a protected foreground store with the durable snapshot, pending readable sources and failure state. Invalid library.json still throws; it cannot become a blank writable library.

A protected store rejects document/journal/media writes and recovered-page creation before writing files. It remains protected for its lifetime: repair requires a fresh open. hasActiveEdits includes unresolved read-only recovery so existing sync/schedule consumers refuse stale-baseline work. Raw Markdown export is separate from committing the library; complete package export remains blocked while recovery is unresolved. RecoveryArchive operations remain independent backup APIs; this protection does not claim a globally immutable directory or block another process's owned operations.

Default app opening and cold foreground window resolution use the new policy. Background resolution retains strict journal refusal. The page shows a static title, explicit read-only marker and selectable Markdown instead of a writing editor. Writing actions are disabled, with raw Markdown rescue still available. The sidebar marks protection and counts readable pending drafts. The recovery sheet exposes each decoded pending source for raw Markdown sharing and retains the recovery notice. No journal is repaired or deleted by a UI action in this change.

## Evidence

Five Core tests cover readable durable data despite a bad neighbor, unchanged JSON/good/bad journal bytes and no durable notifications, central write/journal/package rejection, media/recovered-page/import rejection before file creation, fresh-open recovery after repairing only the test-owned bad file, lifetime protection of the prior rescue store and invalid-library refusal. A facade test exercises the production cold foreground resolver, exact Unicode/CRLF Markdown export of the pending draft, harmless navigation, rejected editing and background resolution rejection. Fresh reopen restores the exact pending source and retains its baseline version.

The original one-argument initializer remains as a convenience initializer. An incremental SwiftPM link failure from old consumers was resolved by preserving this signature; final full-suite receipts are authoritative.

An unreadable journal's undecodable contents cannot be promised recoverable. Readable pending drafts and the durable baseline are snapshots of open time; concurrent changes require reopening. If publication succeeds but subsequent journal cleanup fails, the already committed recovered snapshot remains protected, rather than rolling back committed text or claiming cleanup completed. Broader fault/process/Files/resource/repair UX and full recovery acceptance remain open.

Native QA freshly found the old NativePickerOwnedProxy Xcode access dialog (PID24613), MCP Permission disabled/server not running. No permissions/dialog/server/bridge/session/install/device action occurred. Actual marker/badge, text selection, disabled controls, navigation and Markdown sharing remain natively unverified. No provisioning, CloudKit or TestFlight upload occurred; R01-R15 and pending confirmations remain unchanged.

Final integration: 592 Swift Testing headline with three optional external/native skips and all 58 XCTest passing. Unsigned Debug Simulator and iOS Release builds succeed; SOURCE_HASHES.json and binary receipts record the checked sources.
