# R10 window ownership and native action bars

Baseline: 0588e70. Simulator InstallAndRun was explicitly denied by automatic review; no rerun or alternative UI path.

Files / coverage:
- [x] Sources/SkriptumApp/SkriptumApp.swift: launch state per foreground view, weak native host, host-owned closing lifetime, local marker/request consumption; explicit scene window actions into manually hosted library.
- [x] Sources/SkriptumApp/LocalTasksSheet.swift: QA gate callsite compatibility; two safeAreaBar substitutions.
- [x] Sources/SkriptumBlocks/TableEditingSheet.swift: one safeAreaBar substitution (macOS26+ verified in actual SDK).

No deprecated main-screen/orientation/idiom/layout-guide migrations apply across the audited 236 Swift files. App delegate handles legitimate app/APNs setup; lifecycle is already scene-based. Paper and non-action inset content remains unchanged. No DocumentGroup ordering or document I/O change.

Verification: independent ownership/source review; existing shared window/navigation/data-integrity tests; official iOS/Mac SDK compilation. Actual rotation, keyboard, multiple visible windows and current visual behavior remain unverified after the rejected simulator action. No physical-device release gate.
