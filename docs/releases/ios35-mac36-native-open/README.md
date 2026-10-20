# Scriptum 1.0.2 — iOS 35 / Mac 36

Source: `a8831fe7e2dc134fc1aa7022f1993a8d172d7c5f`.

Native Mac external documents now open through Apple DocumentGroup, save in place, and use document-owned undo. Mac sidebar actions and toolbar controls use compact native controls. Both platforms register Markdown/plain-text documents. Explicit import into an empty library creates its first Space only after source validation.

Targeted checks and visual evidence: `../../qa-mac-openin-20261020/`. Both final Xcode MCP SDK builds and Release archives passed. Signed exports passed 25 iOS and 28 Mac checks; actual package document metadata passed. Both Apple uploads exited 0 and reported Upload succeeded.

## Delivery state

Both uploads accepted, processing started. TestFlight group assignment and Store submission are **not verified or complete**: the App Store Connect browser session expired. iOS 1.0.2 was created and release/review text saved; no build was attached. Cancellation of the previous Mac submission was confirmed in the portal, but its terminal state and the replacement submission still need authenticated portal access. See STATE.json.

No unchanged full-suite, physical-device or iOS runtime tests were repeated. Changed Mac file-open/save/undo paths were exercised with synthetic files. Automated keyboard Undo was inconclusive; native menu Undo/Redo and exact restored bytes passed. No live cross-account CloudKit test was added.

Archives, exported packages, expanded exports, logs and symbols remain in `work/release-ios35-mac36-native-open` under the task workspace. Only the two owned temporary DerivedData directories were removed after successful upload completion.
