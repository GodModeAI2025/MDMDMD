# Scriptum Duo UI verification — 2026-10-23

Official Xcode MCP workspace `workspace-QDiwufs1uX`; iPhone Duo simulator `814CE704-FF44-4F3F-AAA2-7F1E039FB517`, iOS27.2, Xcode27.2. No source changes or commits by UI verifier.

## Proven
- Official destination is eligible; InstallAndRun completed successfully twice (second was reconnect after device-channel loss).
- Start screen at 466×678: native Scriptum title and full library button visible, no overlapping large script wordmark. Paper background remains. See `duo-launch-screenshotPath.png` and hierarchy.
- Actual button tap at hierarchy hitPoint191/186.3 opens visible library All Pages. See `duo-library-tap-screenshotPath.png` and hierarchy.
- New synthetic page created via New Page button, own text entered: “Duo QA 2026-10-23 – eigener Testtext. Auswahl bleibt erhalten.” See `duo-editor-text-screenshotPath.png`.
- Device LandscapeRight event succeeded; app remained Running, text and keyboard focus retained. App UI remained Portrait466×678. Further synthetic text appended successfully and saved indicator visible. See `duo-editor-landscape-*` and `duo-editor-after-rotation-*`.
- Both DeviceInteraction sessions ended (receipts `duo-end-disconnected.json`, `duo-session-end.json`).

## Limits and tool issues
- First LandscapeLeft request and subsequent empty capture returned Channel disconnected; no app-crash evidence. New workspace session + InstallAndRun restored interaction.
- The skill calls the tool DeviceEventSynthesize, while current official bridge exposes DeviceInteractionSynthesize with interactSessionKey.
- Inner display, opening/closing/folding, true width resize and selected-range persistence are NOT verified. Device orientation changed but app UI dimensions did not. Current synth schema has orientation and no fold command.
- DeviceHub CUA launch by bundle and current exact path /Applications/Xcode.app/Contents/Applications/DeviceHub.app failed (timeout then Running application not found). No further retries or unofficial UI routes.
- No Cloud, AI, personal files, account changes, full suite or physical-device tests. Existing app was never uninstalled/reset. Only synthetic new-page test data was added in simulator.

## Additional wide-size evidence — explicitly iPad, NOT fold evidence
- iPad Pro 11-inch (M5), iOS27.2 simulator27E4599C-6F36-4AD7-996C-F75704173B06. Current UI rebuilt/installed via official workspace session successfully.
- Native start scene observed Portrait834×1210 (`ipad-launch-screenshotPath.png`) and Landscape1210×834 (`ipad-launch-landscape-screenshotPath.png`). Full Scriptum title and full library CTA stay in bounds; document browser remains separate below, no overlay or overlap.
- Actual landscape CTA hitPoint605/274 tap opens library NavigationSplitView with sidebar, page list and empty detail (`ipad-library-tap-screenshotPath.png` and hierarchy). Native toolbar title “Alle Seiten” is ellipsized in narrow list column; no overlap/offscreen interactive elements observed.
- No page edits or additional feature tests on iPad; only synthetic welcome state. No app uninstall/reset. Workspace session ended (`ipad-session-end.json`).
- This proves the changed launch layout adapts to a real regular-width runtime; it does NOT prove Duo inner-screen/fold transition.
