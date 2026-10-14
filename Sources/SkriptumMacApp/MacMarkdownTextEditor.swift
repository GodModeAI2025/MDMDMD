import SwiftUI
import AppKit

/// The macOS source editor is an AppKit text system, with native selection,
/// text input, spelling, scrolling, keyboard commands and typing undo.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var preferences: WritingPreferences = .standard
    var isEditable = true
    var jumpTo: Int?
    var command: EditorCommand?
    var onCommandHandled: () -> Void
    var onJumpHandled: (() -> Void)? = nil
    var onCommandUnavailable: (() -> Void)? = nil
    var keyboardRequestID: UUID? = nil
    var onKeyboardRequestHandled: (() -> Void)? = nil
    struct EditorCommand: Equatable { var id = UUID(); var prefix: String; var suffix: String }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 400))
        view.delegate = context.coordinator; view.isRichText = false; view.allowsUndo = true
        view.drawsBackground = false; view.isEditable = isEditable; view.isSelectable = true
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 28, height: 24)
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isContinuousSpellCheckingEnabled = true; view.isGrammarCheckingEnabled = true
        view.string = text; view.setAccessibilityLabel("Markdown-Text")
        scroll.documentView = view; configure(view)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self; view.isEditable = isEditable
        context.coordinator.presenting = true
        defer { context.coordinator.presenting = false }
        if !view.hasMarkedText(), !view.string.utf8.elementsEqual(text.utf8) {
            let old = view.selectedRange(); view.string = text
            // Domain corrections have a separate revision-fenced undo path.
            // Old native typing actions cannot be replayed into a replacement.
            view.undoManager?.removeAllActions()
            let start = min(max(0, old.location), text.utf16.count)
            view.setSelectedRange(NSRange(location: start, length: min(max(0, old.length), text.utf16.count - start)))
        }
        configure(view)
        if let jumpTo, context.coordinator.lastJump != jumpTo {
            context.coordinator.lastJump = jumpTo
            let range = NSRange(location: min(max(0, jumpTo), text.utf16.count), length: 0)
            view.setSelectedRange(range); view.scrollRangeToVisible(range)
            Task { @MainActor in onJumpHandled?() }
        } else if jumpTo == nil { context.coordinator.lastJump = nil }
        if let command, context.coordinator.commandID != command.id, isEditable {
            context.coordinator.commandID = command.id
            Task { @MainActor [weak view, weak coordinator = context.coordinator] in
                guard let view, let coordinator, coordinator.parent.command?.id == command.id else { return }
                let selected = view.selectedRange()
                guard selected.location <= view.string.utf16.count, selected.length <= view.string.utf16.count - selected.location else { coordinator.parent.onCommandUnavailable?(); return }
                let body = (view.string as NSString).substring(with: selected)
                view.insertText(command.prefix + body + command.suffix, replacementRange: selected)
                coordinator.parent.onCommandHandled()
            }
        }
    }
    private func configure(_ view: NSTextView) {
        let font = NSFont.monospacedSystemFont(ofSize: 17 * preferences.fontScale, weight: .regular)
        if view.font != font { view.font = font }
        view.textColor = .labelColor; view.insertionPointColor = .labelColor
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextEditor
        var presenting = false
        var commandID: UUID?
        var lastJump: Int?
        init(_ parent: MarkdownTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard !presenting, let view = notification.object as? NSTextView, parent.isEditable else { return }
            parent.text = view.string; parent.selection = view.selectedRange()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !presenting, let view = notification.object as? NSTextView else { return }
            parent.selection = view.selectedRange()
        }
    }
}
