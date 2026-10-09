# Local proposal comparison UI — fixed-host verification

2026-10-10, Xcode MCP, Arche Rules QA simulator, portrait 402 x 874 pt. Full device-interaction skill read; exclusive session Local Proposal UI Fixed QA. Source frozen; 285-file SHA256 manifests before/after identical.

DEBUG launch argument --scriptum-local-proposal-ui-qa creates isolated temporary library and controlled persisted local proposals. No existing manuscripts touched; no live AI/network/portal/sharing/provisioning operation.

## Results

- Start163 and install164 succeeded. Manager165 showed both controlled tasks; native layout clean and readable. Scrolled166 to actual results.
- Matching result opened via hierarchy hitPoint (201,761.5), receipt167. Ready168 stayed presented and showed Original and Vorschlag. Accessibility strings retain decomposed e + combining acute accent and fox: Original der UI-Prüfung: é und 🦊. / Übernommener UI-Testvorschlag: é und 🦊. Both visible, wrapped cleanly, no overlap/truncation.
- Explicitly tapped actual Änderungen übernehmen at (201,776.5), receipt169, only isolated fixture. Receipt170 shows Bereits übernommen; date 10. Oct 2026 at 01:22; Spätere Änderungen an deiner Seite bleiben erhalten. Acceptance control absent.
- Neu prüfen171 retained identical accepted receipt/date and no apply control. Schließen172 returned to manager; reopening173/174 showed same Bereits übernommen receipt. This verifies dialog reopen persistence, not process-restart persistence.
- Closed175 and opened actual stale result176 at (201,644.5). Ready177 explained that page changed since proposal creation and new proposal should use current version. Actual acceptance Button is Disabled in hierarchy and visibly disabled. Neu prüfen178 preserved same rejection/Disabled state. Schließen179 returned to manager.
- All captures classify app Running; final pid unchanged. No presentation-host errors observed in collected log. Heavy session ended180 (Session stopped); lightweight proxy retained.

## Visual/localization observations

No clipped labels, overlap, invisible text or broken alignment at tested402pt/default Dynamic Type. Minor locale inconsistency: German app copy but receipt date uses English Oct/at, consistent with simulator locale. Wider iPad/resizing and accessibility-size Dynamic Type untested. Matching receipt removes comparison text after apply; accepted state is clear.

## Evidence limit

Controlled persisted fixtures exercise actual manager, review model, apply action and receipt UI. They do not establish provider execution, actual scheduled activation, physical-device or CloudKit/TestFlight behavior. No crash/restart or live billing test.
