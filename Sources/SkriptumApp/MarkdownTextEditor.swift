import SwiftUI
import UIKit

struct MarkdownTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var jumpTo: Int?
    var command: EditorCommand?
    var onCommandHandled: () -> Void
    var onJumpHandled: (() -> Void)? = nil
    var onCommandUnavailable: (() -> Void)? = nil

    struct EditorCommand: Equatable {
        var id = UUID()
        var prefix: String
        var suffix: String
    }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 18, weight: .regular))
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 80, right: 20)
        view.keyboardDismissMode = .interactive
        view.autocorrectionType = .yes
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.accessibilityLabel = "Markdown-Text"
        view.text = text
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if !(view.text ?? "").utf8.elementsEqual(text.utf8) {
            let old = view.selectedRange
            view.text = text
            view.selectedRange = NSRange(location: min(old.location, (text as NSString).length), length: 0)
        }
        if let command, context.coordinator.handledCommand != command.id {
            context.coordinator.handledCommand = command.id
            DispatchQueue.main.async {
                guard context.coordinator.parent.command?.id == command.id else { return }
                guard view.isFirstResponder, view.markedTextRange == nil else {
                    onCommandUnavailable?(); onCommandHandled(); return
                }
                let value = BlockEditorCommand(id: command.id, prefix: command.prefix, suffix: command.suffix)
                if value.isLineStyle {
                    guard let edit = MarkdownLineStyling.applying(value, to: view.text, selection: view.selectedRange) else {
                        onCommandUnavailable?(); onCommandHandled(); return
                    }
                    view.undoManager?.beginUndoGrouping()
                    view.selectedRange = NSRange(location: 0, length: view.text.utf16.count)
                    view.insertText(edit.source)
                    view.selectedRange = edit.selection
                    view.undoManager?.setActionName("Blockstil")
                    view.undoManager?.endUndoGrouping()
                } else {
                    guard let edit = BlockCommandEditing.applying(value, to: view.text, selection: view.selectedRange) else {
                        onCommandUnavailable?(); onCommandHandled(); return
                    }
                    view.selectedRange = edit.replacementRange
                    view.insertText(edit.replacement)
                    view.selectedRange = edit.selection
                }
                context.coordinator.textViewDidChange(view)
                onCommandHandled()
            }
        }
        if let jumpTo, context.coordinator.lastJump != jumpTo {
            context.coordinator.lastJump = jumpTo
            let range = NSRange(location: min(jumpTo, (view.text as NSString).length), length: 0)
            view.selectedRange = range
            view.scrollRangeToVisible(range)
            DispatchQueue.main.async { onJumpHandled?() }
        } else if jumpTo == nil {
            context.coordinator.lastJump = nil
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownTextEditor
        var handledCommand: UUID?
        var lastJump: Int?
        init(_ parent: MarkdownTextEditor) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        func textViewDidChangeSelection(_ textView: UITextView) { parent.selection = textView.selectedRange }
    }
}
