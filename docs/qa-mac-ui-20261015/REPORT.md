# Native Mac visual refinement · 15 October 2026

Request: “mac ui ist noch nicht schön”. The changes apply only to the native Mac interface. The actual app was inspected and operated with its existing isolated Debug-library launch argument and QA preference suite. Personal documents were not used for the screenshots.

## Result

- Library and page-list backgrounds now carry a restrained version of the existing paper surface. System selection colors, native toolbar controls and semantic text colors remain in use in both appearances.
- A smaller brand block, a library descriptor, page-count badges and a serif page-list heading establish the navigation hierarchy. New Page sits beside the page-list heading. Empty previews have an explicit label; rows can grow rather than clipping at a fixed height.
- The writing canvas has more breathing room and no duplicate editable title strip above the document. The separate library title remains editable in Info → Seite → Titel. Word and character counts move to a quiet status strip. Existing writing preferences still take precedence. Inspector tabs use a compact control size and the title field wraps within its panel.
- A labeled Lektorat toolbar button opens the existing proofreading dialog directly. Formatting, assistant, export, view switching and inspector commands retain their existing execution guards.
- The empty editor explains how to begin and has a working New Page button.
- Opening the inspector or narrowing its window below the chosen 1,200-point layout threshold hides the leading library column through the native split-view visibility binding. This keeps the page list, editor and inspector usable; the standard sidebar button restores the library. The 900-point window case was checked in the running app.

## Actual checks

The final native Mac target built through Xcode MCP; see `xcode-mcp-build.json` and its full build log. No shared iOS source changed, so this pass does not claim a new iOS build.

In the running app: created a blank page from the list header, pasted a 528-character Markdown/Unicode witness in the source editor, relaunched the app, renamed the page through the inspector, searched for a nonexistent term and cleared it, and switched writing/source/preview. The full source witness occurs exactly in the real source editor's accessibility value after relaunch (`source-verified.txt` and `source-verified-final.txt`); the visible counter shows 84 words and 528 characters. A direct container-file read was refused by macOS, so no disk-level byte inspection is claimed.

Opened and closed the Info, Comments and History inspector; toggled the native sidebar with the inspector visible; inspected light, dark and restored System appearance. Used the macOS Window → Move & Resize → Top and Left commands to verify both a shorter, wider window and the 900-point minimum-width window. Opened the inspector while narrow and resized an already-open inspector from wide to narrow; the leading library column hides in both cases. The full 528-character source witness remains exact after these final interactions. Opened and closed the direct Lektorat dialog. Source inspection confirms that the existing proofreading action starts automatically on presentation; a response preview appeared with Apple Private Cloud Compute selected. The result was not applied. This UI check does not independently verify the provider transport, PCC runtime guarantees or proofreading quality.

`final-light.png` and `final-dark.png` show the final writing/library appearance. `inspector-light-final.png` and `inspector-dark-final.png` show the compact final inspector. `narrow-inspector-before.png`, `narrow-inspector-after.png` and `narrow-inspector-light-final.png` retain the discovered narrow-window defect and its correction. Inspector first-pass images remain as iteration evidence. `before-dark.png` preserves the original view. `lektorat-dialog.png` shows the real dialog reached by the new button.

## Rejected layout experiment

A combined-library focus layout could hide both navigation panes, but opening the inspector caused an AppKit constraint-update loop and SIGABRT. A simpler variant also failed. The experiment was removed, including its custom focus button and shortcut. The final implementation retains the existing three-column NavigationSplitView and native sidebar toggle. The same inspector-opening sequence subsequently passed, including mode changes, appearance changes and window resizing. Sanitized exception-symbol records retain the failure evidence without full machine diagnostic metadata. No combined-library focus feature is delivered by this change.

## Delivery boundary

This is a source/UI checkpoint, with local Mac build and interaction evidence. It is not a new TestFlight upload, App Review submission, live iCloud/PCC verification, exhaustive resize test or accessibility certification. Earlier release receipts and other open product requirements remain separate.
