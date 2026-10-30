# Native macOS layout verification — 2026-10-30

Verified candidate: MacManuscriptSurface flexible frame adds minHeight: 0. Native Debug build succeeded in 3.695 seconds. QA launch uses only isolated sandbox test library; synthetic page and layout-probe.md contain no personal content.

## Root cause
The 1280×820 native window hosted NavigationSplitRepresentable at (0, -149, 1280, 1158.5), clipping sidebar brand, heading, and search above the titlebar. Native content safe-area top was a correct 40 points. After the fix the split frame became (0, 0, 1280, 820). See geometry-tree.json and candidate4-geometry-import.json.

## Visual checks
- Fresh unselected welcome: PASS, candidate4-welcome.png.
- Selected page: PASS, candidate4-selected.png.
- Selected page to empty Favorites: PASS, candidate4-empty-favorites.png.
- Compact resize, approximately 902×600 points: PASS, candidate4-compact.png.
- Native sidebar hide and restore: PASS, candidate4-sidebar-hidden.png and candidate4-sidebar-restored.png.
- Native View > Enter Full Screen > Exit Full Screen: PASS, candidate4-fullscreen.png.
- Native File > Open of synthetic layout-probe.md: PASS, candidate4-external-document.png and .ax.txt.

## Scope and cleanup
No production code edited by QA agent. No personal documents changed, no cloud or AI requests, no full unchanged test suite. Previous owned debug processes and their stale debugger were closed; final QA process 79413 was terminated after verification. Evidence retained. Native hierarchy and real window captures used; no UI injection.

## Tool caveat
Xcode RunProject can leave earlier app instances alive. Candidate1 first run was stale and explicitly re-tested as candidate1-clean-welcome.png. Candidate1, expanded toolbar candidate2, and added toolbar-button candidate3 did not solve the clipping. Final candidate4 had geometry plus fresh process visual confirmation.
