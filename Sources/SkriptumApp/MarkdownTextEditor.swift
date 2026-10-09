import SwiftUI
import UIKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif
#if canImport(SkriptumBlocks)
import SkriptumBlocks
#endif

struct MarkdownTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var preferences: WritingPreferences = .standard
    var isEditable = true
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
        view.isEditable = isEditable
        view.backgroundColor = .clear
        view.adjustsFontForContentSizeCategory = false
        view.textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 80, right: 20)
        view.keyboardDismissMode = .interactive
        view.autocorrectionType = .yes
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.accessibilityLabel = "Markdown-Text"
        view.text = text
        context.coordinator.applyPresentation(to: view)
        view.registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { [weak coordinator = context.coordinator] (view: UITextView, _: UITraitCollection) in
            coordinator?.applyPresentation(to: view)
        }
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = isEditable
        if view.markedTextRange == nil, !(view.text ?? "").utf8.elementsEqual(text.utf8) {
            context.coordinator.presentationDirty = true
            let old = view.selectedRange
            view.text = text
            let count = text.utf16.count, start = min(max(0, old.location), text.utf16.count)
            view.selectedRange = NSRange(location: start, length: min(max(0, old.length), count - start))
        }
        context.coordinator.applyPresentation(to: view)
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
        var lastFont: UIFont?
        var lastSpacing: Double?
        var presenting = false
        var presentationDirty = true
        func applyPresentation(to view: UITextView) {
            guard view.markedTextRange == nil else { return }
            let font = WritingNativePresentation.font(preferences: parent.preferences, baseCodeSize: 18, traits: view.traitCollection)
            guard presentationDirty || lastFont != font || lastSpacing != parent.preferences.lineSpacing else { return }
            presenting = true
            WritingNativePresentation.apply(to: view, font: font, lineSpacing: parent.preferences.lineSpacing, previousFont: lastFont)
            lastFont = font; lastSpacing = parent.preferences.lineSpacing; presentationDirty = false; presenting = false
        }
        init(_ parent: MarkdownTextEditor) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            guard !presenting else { return }
            if textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true { presentationDirty = true }
            applyPresentation(to: textView); parent.text = textView.text
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !presenting else { return }; applyPresentation(to: textView); parent.selection = textView.selectedRange
        }
    }
}
