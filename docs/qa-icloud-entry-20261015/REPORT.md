# iPhone iCloud entry regression check — 2026-10-15

**Final accepted navigation candidate:** one visible launch action, initial page list, iCloud access from library toolbar and page menu. Narrow navigation check passed; actual sync remains outside scope. Rejected two-action candidates are preserved below.

Scope: narrow UI discoverability/navigation check on iPhone 17e simulator, iOS 27.0 (24A434), UUID `2E43F14B-6CF1-4FD3-87AF-FD6E2A3E65F9`. Xcode MCP workspace `workspace-GU0n2mrDHO`, scheme Skriptum. No physical-device release gate. No Apple credentials entered and iCloud activation was not pressed. Only the new simulator installation’s synthetic welcome page was opened.

## Initial candidate

- Build/install succeeded via DeviceInteractionInstallAndRun.
- Settled launch exposed only a system **More…** button. The two custom actions appeared in AX behind the document-browser sheet, not as visible direct actions. More opened a popover containing both actions plus a blank middle button. This is a real discoverability/layout failure, not an accepted result. Evidence: `icloud-entry-launch-settled.png/.txt`, `icloud-entry-launch-more.png/.txt`.
- More → Spaces und Bibliothek öffnen opened **Alle Seiten**, showing the synthetic welcome page in a list. It did not automatically open that page. Evidence: `icloud-entry-library.png/.txt`.
- The library cloud toolbar button opened the real iCloud settings sheet, showing Lokal verfügbar, iCloud aktivieren, Seitenkonflikte prüfen, Diagnose, and Fertig. Evidence: `icloud-entry-library-dialog.png/.txt`. No cloud activation performed.
- Opening the synthetic welcome page, then Mehr → iCloud-Synchronisation opened the same actual iCloud settings sheet. The menu label wraps naturally on this phone width and remains readable. Evidence: `icloud-entry-page-more.png/.txt`, `icloud-entry-page-dialog.png/.txt`.
- Normal return to launch is Dateien → Zum Dateibrowser. Back navigation first returns to the sidebar. No source text was edited.

## Revised candidate

Parent replaced nested VStack with Group. Rebuild/install succeeded. The settled launch **still failed**: More… remained the only visible action, and both custom AX buttons overlapped at y422 behind the document browser. More showed both labels plus a blank unlabeled middle action. Evidence: `icloud-entry-group-launch.png/.txt`, `icloud-entry-group-more.png/.txt`.

The iCloud action reached through More did successfully open the real iCloud settings sheet after the transition settled; it was not blank or hidden. Evidence: `icloud-entry-group-direct-dialog-settled.png/.txt`. This passes presentation timing only, not launch discoverability.

Parent was notified to flatten the actions directly into DocumentGroupLaunchScene. This report does **not** accept the final launch layout; that candidate has not yet been built or checked.

DeviceInteractionEndSession returned Session stopped at the end of this check. Xcode access released to parent; no simulator session left open by this agent.

## Limits

Navigation evidence does not prove iCloud authentication, data upload, receipt, cross-device merging, or the reporter’s TestFlight sync defect fixed. No new TestFlight feedback was available within this simulator check.

## Direct scene-child candidate (final check in this session)

The two Buttons were flattened directly into DocumentGroupLaunchScene, with the DEBUG QA cover moved to the launch background. One new simulator session and one build/install succeeded. **Layout still fails:** the settled launch has only More… visible. Its popover still contains both labeled actions and an unlabeled middle button. Evidence: `icloud-entry-final-launch.png/.txt`, `icloud-entry-final-more.png/.txt`. The two custom AX action views overlap at y422 behind the document browser, so their AX presence is not accepted as visual discoverability. No additional direct-route success is claimed for this candidate; the previously verified Group candidate establishes only that its action wiring can present a real sheet after entering More.

The final check session was ended successfully (Session stopped). No source edits, commits, signing changes, uploads, Apple logins, physical-device actions, or iCloud activation were performed by this verifier. Further launch layout work remains required.

## Accepted final candidate — single launch action

Parent removed the second launch action and the initiallyShowingICloud state, restoring the baseline single-button launch structure. The actual fix remains: no automatic first-page selection, visible library iCloud toolbar access, and page Mehr → iCloud-Synchronisation. One build/install succeeded for this candidate on the same iPhone 17e simulator. Its runtime metadata was iOS build 9; the parent subsequently changed release metadata only to iOS10/Mac13 without another build in this verification session.

All requested checks passed:

1. Settled launch shows **Spaces und Bibliothek öffnen** as a visible, fully readable button at y260. There is no More-only launch action. Evidence: `icloud-entry-single-launch.png/.txt`.
2. Tapping that visible launch button opens **Alle Seiten** and the welcome-page list. It does not automatically open a text. Evidence: `icloud-entry-single-library.png/.txt`.
3. The visible cloud toolbar icon opens the actual iCloud settings sheet, including iCloud aktivieren and Diagnose. Evidence: `icloud-entry-single-library-dialog.png/.txt`.
4. Opening the synthetic welcome page, then Mehr → iCloud-Synchronisation opens the same actual iCloud settings. The menu label wraps onto two readable lines on the 390-point phone width. Evidence: `icloud-entry-single-page-more.png/.txt`, `icloud-entry-single-page-dialog.png/.txt`.

No UI overlap or clipping was observed in the accepted routes. The second direct-launch iCloud action is deliberately absent; it is not a missing acceptance criterion for this final candidate. No iCloud activation was pressed and no source text was edited. DeviceInteractionEndSession returned Session stopped; Xcode was released to parent. The successful navigation check does not prove real device/cloud sync or shipment of this fix.
