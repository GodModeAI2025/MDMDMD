import SwiftUI

#if canImport(UIKit)
import UIKit

struct BlockNativeEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    let kind: WritingBlockKind
    let headingLevel: Int
    let selectionChanged: (NSRange) -> Void
    let command: BlockEditorCommand?
    let commandHandled: (UUID, Bool) -> Void
    let source: String
    let sourceChanged: (String) -> Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityLabel = "\(kind.title) content"
        view.text = text
        view.font = font
        view.selectedRange = clamped(selection, count: text.utf16.count)
        if command == nil { DispatchQueue.main.async { view.becomeFirstResponder() } }
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        // Keep native marked text and cursor intact while a user is composing.
        if view.markedTextRange == nil, !view.text.utf8.elementsEqual(text.utf8) {
            let old = view.selectedRange; view.text = text
            view.selectedRange = clamped(old, count: text.utf16.count)
            context.coordinator.lastPublishedText = text
        }
        let caret = clamped(selection, count: view.text.utf16.count)
        if view.markedTextRange == nil, view.selectedRange != caret { view.selectedRange = caret }
        view.font = font
        context.coordinator.applyCommand(to: view)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
    private var font: UIFont {
        if kind == .code || kind == .table {
            return UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 17, weight: .regular))
        }
        if kind == .heading {
            let style: UIFont.TextStyle = headingLevel <= 1 ? .largeTitle : (headingLevel == 2 ? .title1 : .title3)
            let base = UIFont.preferredFont(forTextStyle: style)
            return UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(.traitBold) ?? base.fontDescriptor, size: 0)
        }
        return UIFont.preferredFont(forTextStyle: .body)
    }
    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockNativeEditor
        var lastPublishedText: String
        var commandGate = BlockCommandGate()
        init(_ parent: BlockNativeEditor) { self.parent = parent; lastPublishedText = parent.text }
        func textViewDidChange(_ view: UITextView) {
            parent.selection = view.selectedRange
            if !lastPublishedText.utf8.elementsEqual(view.text.utf8) {
                lastPublishedText = view.text
                parent.text = view.text
            }
            parent.selectionChanged(view.selectedRange)
            view.invalidateIntrinsicContentSize()
        }
        func textViewDidChangeSelection(_ view: UITextView) {
            parent.selection = view.selectedRange; parent.selectionChanged(view.selectedRange)
        }
        func applyCommand(to view: UITextView) {
            guard let command = parent.command, commandGate.claim(command.id) else { return }
            guard view.isFirstResponder else {
                DispatchQueue.main.async { self.parent.commandHandled(command.id, false) }
                return
            }
            DispatchQueue.main.async {
                guard self.parent.command?.id == command.id else { return }
                guard view.window != nil, view.isFirstResponder, view.markedTextRange == nil,
                    let edit = BlockCommandEditing.applying(command, to: view.text, selection: view.selectedRange) else {
                    self.parent.commandHandled(command.id, false); return
                }
                if command.isLineStyle {
                    self.parent.commandHandled(command.id, self.applyStyle(command, to: view))
                    return
                }
                let undo = view.undoManager
                undo?.beginUndoGrouping()
                view.selectedRange = edit.replacementRange
                // UITextInput's normal insertion path registers a native undo.
                view.insertText(edit.replacement)
                view.selectedRange = edit.selection
                self.textViewDidChange(view)
                undo?.setActionName("Formatieren")
                undo?.endUndoGrouping()
                self.parent.commandHandled(command.id, true)
            }
        }
        func applyStyle(_ command: BlockEditorCommand, to view: UITextView) -> Bool {
            guard ![WritingBlockKind.code, .image, .table].contains(parent.kind) else { return false }
            let oldSource = parent.source, projection = BlockProjection(oldSource), oldSelection = view.selectedRange
            let start = projection.sourceOffset(for: 0), end = projection.sourceOffset(for: projection.text.utf16.count)
            guard let edit = MarkdownLineStyling.applying(command, to: oldSource, selection: NSRange(location: start, length: end - start)) else { return false }
            guard !edit.source.utf8.elementsEqual(oldSource.utf8) else { return true }
            guard parent.sourceChanged(edit.source) else { return true }
            showSource(edit.source, selection: oldSelection, in: view)
            registerStyleUndo(source: oldSource, selection: oldSelection, inverse: edit.source, inverseSelection: view.selectedRange, in: view)
            return true
        }
        func showSource(_ source: String, selection: NSRange, in view: UITextView) {
            let body = BlockProjection(source).text
            if !view.text.utf8.elementsEqual(body.utf8) { view.text = body }
            lastPublishedText = body
            view.selectedRange = clamped(selection, count: body.utf16.count)
            parent.selection = view.selectedRange; parent.selectionChanged(view.selectedRange)
        }
        func registerStyleUndo(source: String, selection: NSRange, inverse: String, inverseSelection: NSRange, in view: UITextView) {
            view.undoManager?.registerUndo(withTarget: self) { [weak view] coordinator in
                MainActor.assumeIsolated {
                    guard let view, coordinator.parent.sourceChanged(source) else { return }
                    coordinator.showSource(source, selection: selection, in: view)
                    coordinator.registerStyleUndo(source: inverse, selection: inverseSelection, inverse: source, inverseSelection: selection, in: view)
                }
            }
            view.undoManager?.setActionName("Blockstil")
        }
    }
}
#elseif canImport(AppKit)
import AppKit

struct BlockNativeEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    let kind: WritingBlockKind
    let headingLevel: Int
    let selectionChanged: (NSRange) -> Void
    let command: BlockEditorCommand?
    let commandHandled: (UUID, Bool) -> Void
    let source: String
    let sourceChanged: (String) -> Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.delegate = context.coordinator
        view.isRichText = false; view.drawsBackground = false; view.allowsUndo = true
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.textContainerInset = .zero; view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.string = text; view.font = font
        view.setSelectedRange(clamped(selection, count: text.utf16.count))
        view.setAccessibilityLabel("\(kind.title) content")
        if command == nil { DispatchQueue.main.async { view.window?.makeFirstResponder(view) } }
        return view
    }
    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.parent = self
        if !view.hasMarkedText(), !view.string.utf8.elementsEqual(text.utf8) {
            let old = view.selectedRange(); view.string = text; view.setSelectedRange(clamped(old, count: text.utf16.count))
            context.coordinator.lastPublishedText = text
        }
        let caret = clamped(selection, count: view.string.utf16.count)
        if !view.hasMarkedText(), view.selectedRange() != caret { view.setSelectedRange(caret) }
        view.font = font
        context.coordinator.applyCommand(to: view)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        nsView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        guard let container = nsView.textContainer, let manager = nsView.layoutManager else { return nil }
        manager.ensureLayout(for: container)
        return CGSize(width: width, height: max(44, manager.usedRect(for: container).height))
    }
    private var font: NSFont {
        if kind == .code || kind == .table { return .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular) }
        if kind == .heading { return .systemFont(ofSize: headingLevel <= 1 ? 32 : (headingLevel == 2 ? 26 : 21), weight: .bold) }
        return .systemFont(ofSize: NSFont.systemFontSize)
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BlockNativeEditor
        var lastPublishedText: String
        var commandGate = BlockCommandGate()
        init(_ parent: BlockNativeEditor) { self.parent = parent; lastPublishedText = parent.text }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.selection = view.selectedRange()
            if !lastPublishedText.utf8.elementsEqual(view.string.utf8) {
                lastPublishedText = view.string; parent.text = view.string
            }
            parent.selectionChanged(view.selectedRange()); view.invalidateIntrinsicContentSize()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.selection = view.selectedRange(); parent.selectionChanged(view.selectedRange())
        }
        func applyCommand(to view: NSTextView) {
            guard let command = parent.command, commandGate.claim(command.id) else { return }
            guard let window = view.window, window.firstResponder === view else {
                DispatchQueue.main.async { self.parent.commandHandled(command.id, false) }
                return
            }
            DispatchQueue.main.async {
                guard self.parent.command?.id == command.id else { return }
                guard let window = view.window, window.firstResponder === view, !view.hasMarkedText(),
                    let edit = BlockCommandEditing.applying(command, to: view.string, selection: view.selectedRange()) else {
                    self.parent.commandHandled(command.id, false); return
                }
                if command.isLineStyle {
                    self.parent.commandHandled(command.id, self.applyStyle(command, to: view))
                    return
                }
                let undo = view.undoManager
                undo?.beginUndoGrouping()
                view.insertText(edit.replacement, replacementRange: edit.replacementRange)
                view.setSelectedRange(edit.selection)
                self.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
                undo?.setActionName("Formatieren")
                undo?.endUndoGrouping()
                self.parent.commandHandled(command.id, true)
            }
        }
        func applyStyle(_ command: BlockEditorCommand, to view: NSTextView) -> Bool {
            guard ![WritingBlockKind.code, .image, .table].contains(parent.kind) else { return false }
            let oldSource = parent.source, projection = BlockProjection(oldSource), oldSelection = view.selectedRange()
            let start = projection.sourceOffset(for: 0), end = projection.sourceOffset(for: projection.text.utf16.count)
            guard let edit = MarkdownLineStyling.applying(command, to: oldSource, selection: NSRange(location: start, length: end - start)) else { return false }
            guard !edit.source.utf8.elementsEqual(oldSource.utf8) else { return true }
            guard parent.sourceChanged(edit.source) else { return true }
            showSource(edit.source, selection: oldSelection, in: view)
            registerStyleUndo(source: oldSource, selection: oldSelection, inverse: edit.source, inverseSelection: view.selectedRange(), in: view)
            return true
        }
        func showSource(_ source: String, selection: NSRange, in view: NSTextView) {
            let body = BlockProjection(source).text
            if !view.string.utf8.elementsEqual(body.utf8) { view.string = body }
            lastPublishedText = body
            view.setSelectedRange(clamped(selection, count: body.utf16.count))
            parent.selection = view.selectedRange(); parent.selectionChanged(view.selectedRange())
        }
        func registerStyleUndo(source: String, selection: NSRange, inverse: String, inverseSelection: NSRange, in view: NSTextView) {
            view.undoManager?.registerUndo(withTarget: self) { [weak view] coordinator in
                MainActor.assumeIsolated {
                    guard let view, coordinator.parent.sourceChanged(source) else { return }
                    coordinator.showSource(source, selection: selection, in: view)
                    coordinator.registerStyleUndo(source: inverse, selection: inverseSelection, inverse: source, inverseSelection: selection, in: view)
                }
            }
            view.undoManager?.setActionName("Blockstil")
        }
    }
}
#endif

private func clamped(_ range: NSRange, count: Int) -> NSRange {
    let start = min(max(0, range.location), count)
    return NSRange(location: start, length: min(max(0, range.length), count - start))
}
