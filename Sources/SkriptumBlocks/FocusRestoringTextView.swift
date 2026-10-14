import Foundation

/// Keeps a requested or interrupted keyboard focus until the editor is in a window again.
/// Size-class changes (rotation) move or recreate native editors outside a window.
public struct WindowFocusRestoration: Sendable, Equatable {
    public private(set) var isPending = false
    public private(set) var retries = 0
    public static let maxRetries = 8
    public init() {}
    public mutating func request() { isPending = true; retries = 0 }
    public mutating func cancel() { isPending = false; retries = 0 }
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
    /// A refused `becomeFirstResponder` (view not yet settled during a rotation or layout pass) must not drop the request.
    public mutating func finished(becameFirstResponder: Bool, isEditable: Bool) -> Bool {
        if becameFirstResponder || !isEditable { retries = 0; return false }
        guard retries < Self.maxRetries else { retries = 0; return false }
        retries += 1; isPending = true
        return true
    }
}

#if canImport(UIKit)
import UIKit

public final class FocusRestoringTextView: UITextView {
    public private(set) var focusRestoration = WindowFocusRestoration()
    private var focusGeneration = UUID()
    public func cancelPendingFocus() { focusGeneration = UUID(); focusRestoration.cancel() }
    /// Focus is requested when the view is actually in a window, not when it is created.
    public func requestFocusInWindow() {
        focusGeneration = UUID()
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
    private func scheduleRestoredFocus(after delay: TimeInterval = 0) {
        guard window != nil, focusRestoration.enteredWindow(isEditable: isEditable) else { return }
        let generation = focusGeneration
        let attempt = { [weak self] in
            guard let self, self.focusGeneration == generation, self.focusRestoration.attempt(inWindow: self.window != nil, isEditable: self.isEditable) else { return }
            let already = self.isFirstResponder
            let focused = already || self.becomeFirstResponder()
            if focused {
                _ = self.focusRestoration.finished(becameFirstResponder: true, isEditable: true)
                // The accessory can come up without the keyboard after a window move; re-resolve both together.
                if !already, self.inputAccessoryView != nil { self.reloadInputViews() }
                if self.isScrollEnabled { self.scrollRangeToVisible(self.selectedRange) }
            } else if self.focusRestoration.finished(becameFirstResponder: false, isEditable: self.isEditable) {
                self.scheduleRestoredFocus(after: 0.06)
            }
        }
        if delay > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: attempt) }
        else { DispatchQueue.main.async(execute: attempt) }
    }
}
#endif
