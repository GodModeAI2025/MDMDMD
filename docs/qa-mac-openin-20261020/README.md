# Native macOS controls and external documents — 20 October 2026

The owner requested better Mac buttons, reliable Finder “Open With”, an iOS/iPadOS impact check, and autonomous TestFlight/App Store delivery. Previously passing unchanged functions were not retested.

## Corrections

- macOS now declares a native `DocumentGroup` before its library scene. Finder and File → Open load the external Markdown document directly, independently of a writable/open library or the importer's folder/image requirements. The existing native library remains the normal launch window; explicit library import remains available with ⇧⌘O. External document edits save to the original file through Apple's coordinated document lifecycle.
- Both apps register Markdown/plain-text document handling and the imported Markdown extension mapping. iOS/iPadOS also explicitly supports opening in place. The retained iOS33 app metadata had no `CFBundleDocumentTypes`; the Mac had no imported Markdown mapping. The new metadata regression failed on both missing declarations and on the absent iOS in-place flag, then passed after correction.
- An explicit import into an empty library now validates the file before creating its destination Space. The new real-library regression failed before the correction and passes afterward. Invalid UTF-8 creates neither page nor Space; the successful import preserves the original bytes.
- Mac sidebar actions use native borderless controls with full-width hit regions and 28-point minimum height. Labels indicate dialogs with ellipses. Toolbar view/AI menus use symbols with meaningful labels/tooltips; Lektorat remains directly labeled. Controls continue to use system appearance and accent colors.

## Actual native verification

The old, healthy library's Finder routing worked in warm and cold launches. Its file handler forced an import; this is distinct from opening an arbitrary Markdown document. An initial ordinary launch also exposed an unavailable remembered library; no personal document or preference was modified. Subsequent UI checks used only an isolated synthetic library and two owned Markdown witnesses.

The corrected native app opened a Markdown file containing relative image syntax in its own document window through Finder's Open With; it did not require an image-folder import. The final candidate repeated this with the app closed. File → Open also opened the ordinary 65-byte witness. A pasted edit was saved to disk, undone through Edit → Undo, redone through Edit → Redo, saved, then undone and saved again. The exact original 65 bytes, CRLF endings, decomposed accent and emoji were restored. See `native-save-proof.json`, `native-restored-proof.json` and `native-cold-open.txt`.

The first document candidate registered undo twice (native NSTextView plus the document binding). That failed the intended single-action behavior. The corrected document view delegates undo registration only to `MarkdownDocument.replaceText`; the ordinary library source editor retains its original native typing undo. Actual menu Undo/Redo and byte checks above cover the corrected candidate. Keyboard shortcut synthesis did not reliably activate Undo in this UI session; no separate hardware-keyboard claim is made.

The full-width New Space row opened the actual dialog; it was cancelled without creating content. The compact library toolbar and external document window were visually inspected and captured. No AI request, cloud invitation, account setting or personal text edit was made.

The UI binary used a temporary Debug-only selection of the already existing QA library path, because the MCP runner did not preserve temporary scheme arguments. This instrumentation and the temporary scheme edit were removed before final SDK builds and Release archives. UI logic is unchanged by their removal; final version numbers are 1.0.2 (35) / (36). `SOURCE_HASHES.json` records final production sources. This is not an iPhone/iPad runtime claim.

## Scope and release

Only the new import and metadata regressions, the changed Mac UI/document path and required native SDK/signing checks are in scope. The accidentally selected iOS simulator **build** after project generation was not a simulator launch and is not labeled as a Mac build; the Mac scheme was explicitly selected afterward. Unchanged grammar, AI, iCloud transport, exports and earlier integrity evidence are reused.

The design uses the owner's linked [Apple Design Skill](https://github.com/dickwu/apple-design-skill) and loaded Apple HIG button, toolbar, menu and macOS guidance. Apple Xcode MCP documentation confirms that document types must be declared and DocumentGroup owns opening/lifecycle behavior. No dependency or GitHub workflow was added.

Delivery and App Store review receipts are recorded separately; local UI/build checks alone do not imply upload, Apple approval or publication.

Final official Xcode MCP builds: native Mac/My Mac passed in 24.218 seconds; iOS/Any iOS Device (arm64) passed in 85.248 seconds, both with no build errors. No physical device or simulator was launched for these final checks.
