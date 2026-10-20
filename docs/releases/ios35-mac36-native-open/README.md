# Scriptum 1.0.2 — iOS 35 / Mac 36

Source: `a8831fe7e2dc134fc1aa7022f1993a8d172d7c5f`.

Native Mac external documents now open through Apple DocumentGroup, save in place, and use document-owned undo. Mac sidebar actions and toolbar controls use compact native controls. Both platforms register Markdown/plain-text documents. Explicit import into an empty library creates its first Space only after source validation.

Targeted checks and visual evidence: `../../qa-mac-openin-20261020/`. Both final Xcode MCP SDK builds and Release archives passed. Signed exports passed 25 iOS and 28 Mac checks; actual package document metadata passed. Both Apple uploads exited 0 and reported Upload succeeded.

## Delivery state

Both uploads accepted and processed. Both builds are **Im Test** in the existing **Mark – Intern** group with one existing tester; German test notes saved. Both Store submissions are **Warten auf Prüfung**, with automatic publication after approval selected.

- iOS 1.0.2 (35), submitted 20 October 2026 at 18:49 Europe/Berlin: `e96ff4e6-0216-499a-9d76-49a13e7f0fad`.
- macOS 1.0.2 (36), submitted at 18:53: `8d2fb6c2-d1fb-4a7c-93a2-a6379f0ccbc6`.
- Previous Mac submission is removed; current review has build 36. iOS live 1.0.1 remains available while this update waits.
- Export compliance answered for both builds using Apple OS-only cryptography scope. No new legal agreement accepted.

Authoritative portal evidence: `ios-store-waiting.png`, `mac-store-waiting.png`, `store-both-waiting.png`, `testflight-both.png`. This is submission and internal availability, **not Apple approval or public publication**.

No unchanged full-suite, physical-device or iOS runtime tests were repeated. Changed Mac file-open/save/undo paths were exercised with synthetic files. Automated keyboard Undo was inconclusive; native menu Undo/Redo and exact restored bytes passed. No live cross-account CloudKit test was added.

Archives, exported packages, expanded exports, logs and symbols remain in `work/release-ios35-mac36-native-open` under the task workspace. Only the two owned temporary DerivedData directories were removed after successful upload completion.
