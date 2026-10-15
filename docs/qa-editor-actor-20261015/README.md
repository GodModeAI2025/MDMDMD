# Actor-bound editor callbacks

15 October 2026. The SwiftUI 27 SDK declares Binding getters/setters as `@isolated(any) @Sendable`, inheriting the actor of the call site. The editor's canonical-source reader and native write callback now explicitly retain `@MainActor @Sendable` through the row and binding helper. Toolbar preference callbacks carry the same contract. No unsafe Sendable conformance, actor assertion or warning suppression was introduced.

Both actual Mac and iOS-arm64 targets build through Xcode MCP. The existing native LiveBinding suite passes five tests (including three render-interleaving cases), covering exact Unicode/CRLF input, selection, Undo/Redo and rejection of foreign revisions. Five preference validation/storage tests pass in two target runs (2 + 3). Tests remain unchanged. An initial evidence aggregation expected one combined test-run headline and was corrected to sum both actual target runs; no test result was changed.

The native Mac Release also builds with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES SWIFT_SUPPRESS_WARNINGS=NO`. No app-source Swift warning is emitted. The pinned swift-markdown dependency still emits migration warnings and the App Intents metadata tool still emits its existing warning; this is not a whole-dependency zero-warning claim. The first strict invocation failed because packages combined warnings-as-errors with suppress-warnings. The initial sandboxed test invocation could not write compiler caches. Both failures and the successful final runs are preserved.

These source changes follow uploaded build 12 and are not included in that binary. The full R01–R15 scope and server-side processing/internal TestFlight verification remain open.
