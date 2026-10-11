# Custom proofreading-server content permission

2026-10-11. Source base55ed856 plus this patch; verification.json binds final source/test/build hashes.

WritingQualitySheet previously called check again after correction/undo/redo, including server mode. Its settings said page content was sent only on explicit Start. The endpoint was also resolved after asynchronous document preparation rather than captured with the intended request.

Remote checking now first captures the HTTPS client, selected language and immutable prepared document, then presents recipient address, content count, language and scope. Only explicit Send invokes the prepared submission. Fresh source/revision checks precede submission and admit findings after completion. A copied submission shares a lock-backed one-use permission, bound to its exact endpoint and ID; missing/wrong/discarded/replayed permission fails before HTTP. The initializer is fileprivate. Cancel, sheet dismissal without starting and replacing a pending request discard it. Oversized source is rejected before a permission token or request is created.

Correct/undo/redo now clear the old results and automatically recheck only native mode. Server mode requires a fresh explicit request. Configuration is disabled during checking; an endpoint change clears the old language selection/catalog. The language-catalog GET carries no document text. Existing HTTPS validation, ephemeral transport, redirect rejection, size bounds, Markdown projection and source-bound corrections remain.

Two new regressions cover exact endpoint/document/language binding, one-use/discard behavior and missing/stale permission rejection before networking. The existing oversized-input test now checks preparation admission. Full629 Swift Testing headline/four opt-in skips plus58XCTest and unsigned Simulator/iOS Release compilation pass. Source inspection verifies all three correction callbacks use the native-only refresh helper; actual UI callback behavior is not inferred from unit tests.

Fresh device-interaction delegate [readiness](../qa-quality-permission-native-20261011/native-readiness.json) still reports Xcode MCP permission disabled/server not running, no native tools/session and no permission/device/transmission actions. The old dialog is absent from that Xcode Archives capture. Native sheet/gesture/cancel/keyboard behavior, actual custom-server HTTP/grammar, full20-language integrated acceptance and current-source signing/TestFlight delivery remain open. This is a scoped fix, not complete App Review/privacy acceptance or a change to R01-R15.
