# Apple review finding — 30 October 2026

Platform/version under review: macOS 1.0.2 (36).
Submission: 8d2fb6c2-d1fb-4a7c-93a2-a6379f0ccbc6.

Current rejection: Guideline 4 – Design. Apple reports overlapping and inaccessible interface options and requests all instances to be corrected. Screenshot: Screenshot-1029-182638.png (copied unchanged as qa/apple-rejection.png).

Observed in the supplied image: the native window controls overlap the library sidebar; the first All Pages row is clipped at the top. The detail pane is in its welcome state, with no selected page. Previous selected-page QA showed a complete toolbar and unobscured sidebar. This difference is the baseline investigation focus, not yet a verified cause.

## Reproduction and measured cause

A fresh native Mac process with isolated synthetic library data reproduces the same welcome-state clipping. Switching to a selected page removes the clipping. Re-testing with explicit process IDs rules out stale app instances.

Read-only Xcode debugger measurement: the native window is 1280 × 820 pt and has a 40 pt top safe area. Its NavigationSplitRepresentable is laid out at (0, −149, 1280, 1158.5), exceeding the window height. Both sidebar brand and page-list header are above the visible content. This is a sizing problem rather than a missing fixed title-bar offset.

Rejected candidates (not retained): forcing toolbar visibility, using an expanded title bar, and adding a welcome toolbar action. All three still clip in a clean native process. Their screenshots and debugger receipts remain under the local `work/mac-layout-20261030-mcp` evidence directory.

## Correction and validation

The shared MacManuscriptSurface flexible frame now specifies `minHeight: 0`, accepting the available height instead of exporting the welcome content’s oversized minimum into NavigationSplitView. This one-line layout change also applies to library editing and external document windows. No title-bar offsets, window hacks or toolbar changes remain.

Read-only debugger verification after correction: NavigationSplitRepresentable frame is now (0, 0, 1280, 820). Native visual checks passed: no selected page/welcome, selected page, selected → empty Favorites, compact window approximately 902 × 600 pt, sidebar hide/show native full-screen enter/exit and File → Open of a synthetic external Markdown file. Screenshots are retained in `qa/`. UI checks used isolated synthetic data; the temporary DEBUG-only QA-root prefix was removed before Release. No personal documents changed.

Release archive/export succeeded on Xcode 27.2 (27B48), SDK macOS 27.2. The actual exported package contains native macOS 1.0.2 (38); all 28 distribution/signature/iCloud/PCC checks passed. The package signature chain was checked outside the restricted sandbox. Unchanged dependencies emit existing warnings; no dependency or unrelated feature changes were made.

No new unit test mirrors this single layout modifier: the pre-fix runtime reproduction, measured geometry and actual native UI transitions are the regression evidence. Unchanged cloud, authentication, AI and broad device tests were not rerun.
