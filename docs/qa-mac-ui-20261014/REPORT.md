# Native Mac UI refinement · 14 October 2026

Scope: the real SwiftUI/AppKit Mac application. The user's request was “mac ui ist noch nicht schön”. No web mock-up or generated replacement interface was used. All captures came from the running Mac app with an isolated Debug library and separate QA preferences; personal documents and iCloud data were not edited.

## Observed journey and changes

1. **Find a page — improved.** The oversized brand/quotation area and undifferentiated page selection competed with navigation. A compact native sidebar, visible search, two-line plain-text previews, modification dates and a muted ink accent now separate library navigation from the writing canvas. Page rows have a consistent height. The native list is recreated when an empty page gains its first preview, invalidating macOS's stale insertion-cell height cache while keeping the selected page in the workspace.
2. **Write and format — improved.** The duplicated large page title and scattered formatting controls were reduced to a compact editable metadata header, three writing/source/preview modes and a Format menu. Native menu commands expose formatting and writing actions with keyboard shortcuts. Mac defaults use a 700-point maximum reading width, 16-point body type and a restrained serif design; explicitly saved Space preferences still win. Inline emphasis is rendered for inactive writing paragraphs without changing their canonical Markdown or editing offsets.
3. **Review a page — improved.** A single Info / Kommentare / Verlauf switch replaces nested inspector navigation. Outline links, word goals and page metadata use compact controls. Comments, replies and revisions use their existing storage and editing guards. App appearance can follow the system or use Light/Dark independently.

## Evidence

- `01-writing-before.jpg`, `02-inspector-before.jpg`: fresh captures of the previous UI.
- `03-writing-first-pass.jpg`, `08-list-height-iteration.jpg`, `09-list-cache-iteration.jpg`: iteration evidence retained, including the cell-height defect found while creating pages.
- `04-writing-dark-after.jpg`, `05-inspector-light-after.jpg`, `06-writing-light-after.jpg`: actual dark/light UI; the inspector capture deliberately retains the active text selection used in the formatting test.
- `10-final-light.jpg` and `11-final-dark.jpg` show the final stable list rows and demonstration text. All demonstration text was entered in the isolated QA library.
- `functional-checks.json`: manual native interactions plus persisted canonical-source/comment assertions.

Verified: Command-B inserts Markdown emphasis around the selected phrase; Edit → Undo restores the original source; writing/source/preview switching preserves Unicode and Markdown; search with no results and clearing search work; Info/Comments/History are reachable; the existing comment quotation and reply remain persisted; both appearance modes render; Shift-Command-N opens a second native window, closing it preserves the first window's selection; hiding the sidebar expands the writing area beside the inspector.

Build evidence: native Mac Debug build succeeded; the active Xcode MCP also built the iOS target successfully after the shared presentation changes. The focused WritingPreferencesStorage tests passed (2 tests), including platform fallback defaults, no implicit persistence and explicit saved preferences taking precedence. Release signing/upload evidence belongs in the corresponding release directory, not in this visual audit.

## Limits

This is a visual and focused functional check on the available Mac. It is not a physical-device matrix, an accessibility certification, a live multi-device iCloud test, a live model/PCC test, or proof of App Review approval. The minimum window size is declared in code; arbitrary window-size coverage is not claimed. Existing user-selected writing preferences are intentionally preserved, so upgraded installations can differ from fresh defaults.
