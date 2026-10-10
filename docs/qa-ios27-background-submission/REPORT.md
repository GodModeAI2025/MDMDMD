# Async background submission UI smoke

2026-10-10. Native Xcode MCP workspace workspace-8LDnl5qbLc; Arche Rules QA simulator (iOS 27.0), portrait 402 × 874 points. Distinct session Async Background Submit UI QA. Skill fully read before interaction. Installed frozen source using only `--scriptum-local-proposal-ui-qa`. Isolated temporary Store fixture; no production documents.

Source integrity before and after interactions, captured before EndSession: 283 Swift/config files, SHA256 `bad10f8e3caad69c037736f9165d7f26a6adb2e191f37428a9227c75328cbbc0`, identical. Excludes .git/.build/Vendor; manifest includes .swift/.yml/.plist/.entitlements/.pbxproj/.resolved.

## Verified native flow

1. InstallAndRun succeeded. Actual TasksManager rendered with controlled proposal fixtures.
2. Tapped fresh hierarchy hitPoint Neue Aufgabe. Creation form showed QA page preselected, default one-shot future date, summary, Apple PCC; empty prompt disabled Entwurf speichern.
3. Entered `ASYNC-PLAN-QA` into actual Auftrag field. No independent task-title field exists; task title derives from selected page. No document rename/edit attempted. Save became enabled.
4. Entwurf speichern returned to actual manager. Full prompt visible with `Entwurf · noch nicht aktiviert` and foreground-only mode.
5. Tapped Abbrechen belonging only to ASYNC-PLAN-QA row using fresh hitPoint. Row changed to `Abgebrochen`; its activation/cancel controls disappeared. Existing proposal fixtures remained active and unchanged. Application continued Running (PID 66233) and manager rendered after cancellation.

This exercises the app's real local draft save/cancel path after the asynchronous background-submission migration. It establishes startup and manager response under this no-background-target fixture. It does not establish OS background submission acceptance, actual BGTask launch, expiry delivery, or execution concurrency. No background mode enabled, activation reviewed/accepted, manual grant, task run, proposal adopted, provider/network call, account/cloud/portal action or production-document mutation performed.

## Visual/runtime observations

No new overlap, clipped heading/action, unreadable text or crash observed in tested manager/new-task screens. PCC task row repeats provider/model `Apple Private Cloud Compute · Apple Private Cloud Compute`; creation/result dates use English `10. Oct 2026` within German UI (pre-existing cosmetic issues). Lower creation sections unmodified and not separately explored. Logs contain simulator AX duplicate-class/missing-category, haptics-file and API-handler messages; no observed app fatal exception or background crash. Raw logs retained.

## Artifacts

- async-01: initial manager, existing isolated fixtures.
- async-02: empty new form.
- async-03: ASYNC-PLAN-QA prompt/save enabled.
- async-04: saved inactive draft.
- async-05: canceled draft.

Each has native screenshot, fresh hierarchy, runtime logs and JSON receipt. async-end.json proves Session stopped; lightweight proxy left live.
