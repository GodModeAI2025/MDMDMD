import Testing
@testable import SkriptumWorkspaceModel

struct LibraryLaunchRequestGateTests {
    @Test func tapBeforeBackgroundAttachmentRemainsPendingUntilReady() {
        var gate = LibraryLaunchRequestGate()
        let request = "first-open"
        #expect(gate.evaluate(request: request, availability: .detached) == .wait)
        #expect(gate.inFlight == nil)
        #expect(gate.evaluate(request: request, availability: .ready) == .present(request))
        #expect(gate.complete(token: request, currentRequest: request, presented: true).isEmpty)
    }
    @Test func tapDuringClosingTransitionWaitsAndThenOpens() {
        var gate = LibraryLaunchRequestGate()
        #expect(gate.evaluate(request: "reopen", availability: .transitioning) == .wait)
        #expect(gate.evaluate(request: "reopen", availability: .ready) == .present("reopen"))
    }
    @Test func failedPresentationKeepsRequestForRetry() {
        var gate = LibraryLaunchRequestGate()
        #expect(gate.evaluate(request: "open", availability: .ready) == .present("open"))
        let pending = gate.complete(token: "open", currentRequest: "open", presented: false)
        #expect(pending == "open")
        #expect(gate.evaluate(request: pending, availability: .ready) == .present("open"))
    }
    @Test func inFlightPresentationCannotOpenDuplicateOrLoseNewerTap() {
        var gate = LibraryLaunchRequestGate()
        #expect(gate.evaluate(request: "first", availability: .ready) == .present("first"))
        #expect(gate.evaluate(request: "second", availability: .ready) == .wait)
        let pending = gate.complete(token: "first", currentRequest: "second", presented: true)
        #expect(pending == "second")
        #expect(gate.evaluate(request: pending, availability: .visible) == .consume("second"))
    }
    @Test func staleCompletionCannotClearCurrentPresentation() {
        var gate = LibraryLaunchRequestGate()
        #expect(gate.evaluate(request: "current", availability: .ready) == .present("current"))
        #expect(gate.complete(token: "old", currentRequest: "current", presented: true) == "current")
        #expect(gate.inFlight == "current")
    }
    @Test func windowRequestsAreIndependentAndRebuiltBackgroundRecognizesVisibleHost() {
        var first = LibraryLaunchRequestGate(), second = LibraryLaunchRequestGate()
        #expect(first.evaluate(request: "window-one", availability: .ready) == .present("window-one"))
        #expect(second.evaluate(request: "window-two", availability: .ready) == .present("window-two"))
        var rebuilt = LibraryLaunchRequestGate()
        #expect(rebuilt.evaluate(request: "window-one", availability: .visible) == .consume("window-one"))
        #expect(rebuilt.evaluate(request: "", availability: .ready) == .wait)
        #expect(second.inFlight == "window-two")
    }
}
