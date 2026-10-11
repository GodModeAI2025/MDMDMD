# Open an incomplete recovery as an editable text copy

Source-only recovery previously retained readable/exportable text, but a missing image prevented opening it as a new page inside Scriptum. The recovery sheet now offers “Textkopie ohne Bilder öffnen” for incomplete captures, explains retained Markdown image references and original recovery retention, and reports action errors.

The shared recovery path creates a new page in one library commit, retaining exact source/block IDs and writing metadata, but the explicitly selected text copy does not claim image attachments. It verifies durable metadata/source readback, reloads the page list and leaves the original recovery record/media intact. Full restoration remains available later and still validates all attachments before consuming the original. Normal recovery is unchanged; unavailable-library/Space failures now expose an error rather than silently returning nil.

## Verification scope

Two new model regressions cover:

- Exact Unicode/decomposed-accent/CRLF source and Markdown image references, block IDs, tags/favorite/goal/rules/purpose, durable reopen, original record retention and subsequent full media restoration without removing the text copy.
- A stale LibraryStore rejects text-copy creation after another writer commits, preserving the recovery and external state.

The final full suite passes: 569 Swift Testing headline with three optional skips, plus all 58 XCTest checks. Unsigned Debug Simulator and iOS Release compilation both succeed. FULL_TESTS.txt, compile receipts and SOURCE_HASHES.json capture the final source verification. Model/Core checks do not prove native navigation, accessibility or file sharing.

The device-interaction agent freshly read Xcode: old NativePickerOwnedProxy approval dialog PID24613 still present; Permission disabled, mcp-server not running. No dialog click, permission change, replacement bridge, device session or installation occurred. The new button, explanatory text and actual native editor navigation remain unverified. Existing specific approval questions remain unanswered; this change does not establish provisioning, iCloud collaboration or current-source TestFlight delivery. The full R01-R15 acceptance matrix remains binding.
