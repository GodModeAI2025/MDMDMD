import Testing
@testable import SkriptumBlocks
@Test func focusedEditorRestoresAfterWindowMove() {
    var focus = WindowFocusRestoration()
    focus.leavingWindow(wasFirstResponder: true)
    let r1 = focus.enteredWindow(isEditable: true); #expect(r1)
    let r2 = focus.attempt(inWindow: false, isEditable: true); #expect(!r2)
    #expect(focus.isPending)
    let r3 = focus.attempt(inWindow: true, isEditable: true); #expect(r3)
    #expect(!focus.isPending)
    let r4 = focus.attempt(inWindow: true, isEditable: true); #expect(!r4)
}
@Test func dismissedKeyboardStaysDismissedAcrossWindowMove() {
    var focus = WindowFocusRestoration()
    focus.leavingWindow(wasFirstResponder: false)
    let r5 = focus.enteredWindow(isEditable: true); #expect(!r5)
    let r6 = focus.attempt(inWindow: true, isEditable: true); #expect(!r6)
}
@Test func creationRequestWaitsForWindowAndSurvivesInterruptedAttempt() {
    var focus = WindowFocusRestoration()
    focus.request()
    let r7 = focus.enteredWindow(isEditable: true); #expect(r7)
    // Removed again before the deferred attempt ran: the request survives.
    focus.leavingWindow(wasFirstResponder: false)
    #expect(focus.isPending)
    let r8 = focus.enteredWindow(isEditable: true); #expect(r8)
    let r9 = focus.attempt(inWindow: true, isEditable: true); #expect(r9)
    #expect(!focus.isPending)
}
@Test func readOnlyEditorNeverRestoresFocus() {
    var focus = WindowFocusRestoration()
    focus.leavingWindow(wasFirstResponder: true)
    let r10 = focus.enteredWindow(isEditable: false); #expect(!r10)
    #expect(!focus.isPending)
    focus.request()
    let r11 = focus.attempt(inWindow: true, isEditable: false); #expect(!r11)
    #expect(!focus.isPending)
}
