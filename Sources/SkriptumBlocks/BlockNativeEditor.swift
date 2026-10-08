import SwiftUI

#if canImport(UIKit)
import UIKit

struct BlockNativeEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    let kind: WritingBlockKind
    let headingLevel: Int
    let selectionChanged: (NSRange) -> Void
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
        DispatchQueue.main.async { view.becomeFirstResponder() }
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        // Keep native marked text and cursor intact while a user is composing.
        if view.markedTextRange == nil, !view.text.utf8.elementsEqual(text.utf8) {
            let old = view.selectedRange; view.text = text
            view.selectedRange = clamped(old, count: text.utf16.count)
        }
        view.font = font
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
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockNativeEditor
        init(_ parent: BlockNativeEditor) { self.parent = parent }
        func textViewDidChange(_ view: UITextView) {
            parent.selection = view.selectedRange
            parent.text = view.text
            parent.selectionChanged(view.selectedRange)
            view.invalidateIntrinsicContentSize()
        }
        func textViewDidChangeSelection(_ view: UITextView) {
            parent.selection = view.selectedRange; parent.selectionChanged(view.selectedRange)
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
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.delegate = context.coordinator
        view.isRichText = false; view.drawsBackground = false
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.textContainerInset = .zero; view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.string = text; view.font = font
        view.setSelectedRange(clamped(selection, count: text.utf16.count))
        view.setAccessibilityLabel("\(kind.title) content")
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }
    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.parent = self
        if !view.hasMarkedText(), !view.string.utf8.elementsEqual(text.utf8) {
            let old = view.selectedRange(); view.string = text; view.setSelectedRange(clamped(old, count: text.utf16.count))
        }
        view.font = font
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
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BlockNativeEditor
        init(_ parent: BlockNativeEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.selection = view.selectedRange(); parent.text = view.string
            parent.selectionChanged(view.selectedRange()); view.invalidateIntrinsicContentSize()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.selection = view.selectedRange(); parent.selectionChanged(view.selectedRange())
        }
    }
}
#endif

private func clamped(_ range: NSRange, count: Int) -> NSRange {
    let start = min(max(0, range.location), count)
    return NSRange(location: start, length: min(max(0, range.length), count - start))
}
