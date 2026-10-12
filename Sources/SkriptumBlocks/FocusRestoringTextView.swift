import Foundation

/// Keeps a requested or interrupted keyboard focus until the editor is in a window again.
/// Size-class changes (rotation) move or recreate native editors outside a window.
public struct WindowFocusRestoration: Sendable, Equatable {
    public private(set) var isPending = false
    public init() {}
    public mutating func request() { isPending = true }
    /// A dismissed keyboard stays dismissed; only an active or unfinished focus survives.
    public mutating func leavingWindow(wasFirstResponder: Bool) { isPending = isPending || wasFirstResponder }
    public mutating func enteredWindow(isEditable: Bool) -> Bool {
        if !isEditable { isPending = false }
        return isPending
    }
    /// Consumes the request only when the deferred attempt actually runs inside a window.
    public mutating func attempt(inWindow: Bool, isEditable: Bool) -> Bool {
        guard inWindow else { return false }
        defer { isPending = false }
        return isPending && isEditable
    }
}

#if canImport(UIKit)
import UIKit

public final class FocusRestoringTextView: UITextView {
    public private(set) var focusRestoration = WindowFocusRestoration()
    /// Focus is requested when the view is actually in a window, not when it is created.
    public func requestFocusInWindow() {
        focusRestoration.request()
        scheduleRestoredFocus()
    }
    public override func willMove(toWindow newWindow: UIWindow?) {
        if window != nil, newWindow !== window {
            focusRestoration.leavingWindow(wasFirstResponder: isFirstResponder)
        }
        super.willMove(toWindow: newWindow)
    }
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        scheduleRestoredFocus()
    }
    private func scheduleRestoredFocus() {
        guard window != nil, focusRestoration.enteredWindow(isEditable: isEditable) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.focusRestoration.attempt(inWindow: self.window != nil, isEditable: self.isEditable) else { return }
            self.becomeFirstResponder()
            if self.isScrollEnabled { self.scrollRangeToVisible(self.selectedRange) }
        }
    }
}
#endif
