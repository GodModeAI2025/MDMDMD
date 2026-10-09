import SwiftUI
#if canImport(SkriptumCore)
import SkriptumCore
#endif

#if canImport(UIKit)
import UIKit

@MainActor public enum WritingNativePresentation {
    public static func font(preferences: WritingPreferences, kind: WritingBlockKind = .code, headingLevel: Int = 0, rawSourcePresentation: Bool = false, baseCodeSize: CGFloat = 17, traits: UITraitCollection) -> UIFont {
        let style: UIFont.TextStyle = kind == .heading && !rawSourcePresentation ? (headingLevel <= 1 ? .largeTitle : (headingLevel == 2 ? .title1 : .title3)) : .body
        if rawSourcePresentation || kind == .code || kind == .table {
            return UIFontMetrics(forTextStyle: style).scaledFont(for: .monospacedSystemFont(ofSize: baseCodeSize * preferences.fontScale, weight: .regular), compatibleWith: traits)
        }
        let base = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
        let design: UIFontDescriptor.SystemDesign
        switch preferences.fontDesign { case .system: design = .default; case .serif: design = .serif; case .rounded: design = .rounded; case .monospaced: design = .monospaced }
        var descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
        if kind == .heading { descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitBold)) ?? descriptor }
        return UIFont(descriptor: descriptor, size: base.pointSize * preferences.fontScale)
    }
    public static func apply(to view: UITextView, font: UIFont, lineSpacing: Double, previousFont: UIFont?) {
        guard view.markedTextRange == nil else { return }
        let selection = view.selectedRange, undo = view.undoManager
        let registered = undo?.isUndoRegistrationEnabled == true
        if registered { undo?.disableUndoRegistration() }
        view.textStorage.beginEditing()
        view.textStorage.enumerateAttributes(in: NSRange(location: 0, length: view.textStorage.length)) { attributes, range, _ in
            let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.lineSpacing = lineSpacing
            var traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits.intersection([.traitBold, .traitItalic]) ?? []
            traits.subtract(previousFont?.fontDescriptor.symbolicTraits.intersection([.traitBold, .traitItalic]) ?? [])
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits)) ?? font.fontDescriptor
            view.textStorage.addAttributes([.font: UIFont(descriptor: descriptor, size: font.pointSize), .paragraphStyle: style], range: range)
        }
        view.textStorage.endEditing()
        var typing = view.typingAttributes
        let style = (typing[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        var typingTraits = (typing[.font] as? UIFont)?.fontDescriptor.symbolicTraits.intersection([.traitBold, .traitItalic]) ?? []
        typingTraits.subtract(previousFont?.fontDescriptor.symbolicTraits.intersection([.traitBold, .traitItalic]) ?? [])
        let typingDescriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(typingTraits)) ?? font.fontDescriptor
        typing[.font] = UIFont(descriptor: typingDescriptor, size: font.pointSize); typing[.paragraphStyle] = style
        view.typingAttributes = typing
        if registered { undo?.enableUndoRegistration() }
        view.selectedRange = selection
        view.invalidateIntrinsicContentSize()
    }
}

struct BlockNativeEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    let kind: WritingBlockKind
    let headingLevel: Int
    var preferences: WritingPreferences = .standard
    var rawSourcePresentation = false
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
        view.adjustsFontForContentSizeCategory = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityLabel = "\(kind.title) content"
        view.text = text
        context.coordinator.applyPresentation(to: view)
        view.registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { [weak coordinator = context.coordinator] (view: UITextView, _: UITraitCollection) in
            coordinator?.applyPresentation(to: view)
        }
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
            context.coordinator.presentationDirty = true
        }
        let caret = clamped(selection, count: view.text.utf16.count)
        if view.markedTextRange == nil, view.selectedRange != caret { view.selectedRange = caret }
        context.coordinator.applyPresentation(to: view)
        context.coordinator.applyCommand(to: view)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockNativeEditor
        var lastPublishedText: String
        var commandGate = BlockCommandGate()
        var lastFont: UIFont?
        var lastSpacing: Double?
        var presenting = false
        var presentationDirty = true
        func applyPresentation(to view: UITextView) {
            guard view.markedTextRange == nil else { return }
            let font = WritingNativePresentation.font(preferences: parent.preferences, kind: parent.kind, headingLevel: parent.headingLevel, rawSourcePresentation: parent.rawSourcePresentation, traits: view.traitCollection)
            guard presentationDirty || lastFont != font || lastSpacing != parent.preferences.lineSpacing else { return }
            presenting = true
            WritingNativePresentation.apply(to: view, font: font, lineSpacing: parent.preferences.lineSpacing, previousFont: lastFont)
            lastFont = font; lastSpacing = parent.preferences.lineSpacing; presentationDirty = false; presenting = false
        }
        init(_ parent: BlockNativeEditor) { self.parent = parent; lastPublishedText = parent.text }
        func textViewDidChange(_ view: UITextView) {
            guard !presenting else { return }
            if view.undoManager?.isUndoing == true || view.undoManager?.isRedoing == true { presentationDirty = true }
            applyPresentation(to: view)
            parent.selection = view.selectedRange
            if !lastPublishedText.utf8.elementsEqual(view.text.utf8) {
                lastPublishedText = view.text
                parent.text = view.text
            }
            parent.selectionChanged(view.selectedRange)
            view.invalidateIntrinsicContentSize()
        }
        func textViewDidChangeSelection(_ view: UITextView) {
            guard !presenting else { return }
            applyPresentation(to: view)
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
            guard let edit = MarkdownLineStyling.applying(command, to: oldSource, selection: projection.isRawSource ? oldSelection : NSRange(location: start, length: end - start)) else { return false }
            guard !edit.source.utf8.elementsEqual(oldSource.utf8) else { return true }
            guard parent.sourceChanged(edit.source) else { return true }
            showSource(edit.source, selection: oldSelection, in: view)
            registerStyleUndo(source: oldSource, selection: oldSelection, inverse: edit.source, inverseSelection: view.selectedRange, in: view)
            return true
        }
        func showSource(_ source: String, selection: NSRange, in view: UITextView) {
            let body = BlockProjection(source).text
            if !view.text.utf8.elementsEqual(body.utf8) { view.text = body }
            lastPublishedText = body; presentationDirty = true
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

@MainActor public enum WritingNativePresentation {
    public static func font(preferences: WritingPreferences, kind: WritingBlockKind = .code, headingLevel: Int = 0, rawSourcePresentation: Bool = false) -> NSFont {
        let size = (kind == .heading && !rawSourcePresentation ? (headingLevel <= 1 ? 32.0 : (headingLevel == 2 ? 26.0 : 21.0)) : Double(NSFont.systemFontSize)) * preferences.fontScale
        let base = rawSourcePresentation || kind == .code || kind == .table ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular) : NSFont.systemFont(ofSize: size, weight: kind == .heading ? .bold : .regular)
        if rawSourcePresentation || kind == .code || kind == .table { return base }
        let design: NSFontDescriptor.SystemDesign
        switch preferences.fontDesign { case .system: design = .default; case .serif: design = .serif; case .rounded: design = .rounded; case .monospaced: design = .monospaced }
        return base.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }
    public static func apply(to view: NSTextView, font: NSFont, lineSpacing: Double, previousFont: NSFont?) {
        guard !view.hasMarkedText(), let storage = view.textStorage else { return }
        let selections = view.selectedRanges, undo = view.undoManager, registered = view.undoManager?.isUndoRegistrationEnabled == true
        if registered { undo?.disableUndoRegistration() }
        storage.beginEditing()
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, range, _ in
            let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.lineSpacing = lineSpacing
            var traits = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits.intersection([.bold, .italic]) ?? []
            traits.subtract(previousFont?.fontDescriptor.symbolicTraits.intersection([.bold, .italic]) ?? [])
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits))
            storage.addAttributes([.font: NSFont(descriptor: descriptor, size: font.pointSize) ?? font, .paragraphStyle: style], range: range)
        }
        storage.endEditing()
        var typing = view.typingAttributes
        let style = (typing[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        var typingTraits = (typing[.font] as? NSFont)?.fontDescriptor.symbolicTraits.intersection([.bold, .italic]) ?? []
        typingTraits.subtract(previousFont?.fontDescriptor.symbolicTraits.intersection([.bold, .italic]) ?? [])
        let typingDescriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(typingTraits))
        typing[.font] = NSFont(descriptor: typingDescriptor, size: font.pointSize) ?? font; typing[.paragraphStyle] = style; view.typingAttributes = typing
        if registered { undo?.enableUndoRegistration() }
        view.selectedRanges = selections; view.invalidateIntrinsicContentSize()
    }
}

struct BlockNativeEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    let kind: WritingBlockKind
    let headingLevel: Int
    var preferences: WritingPreferences = .standard
    var rawSourcePresentation = false
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
        view.string = text; context.coordinator.applyPresentation(to: view)
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
            context.coordinator.presentationDirty = true
        }
        let caret = clamped(selection, count: view.string.utf16.count)
        if !view.hasMarkedText(), view.selectedRange() != caret { view.setSelectedRange(caret) }
        context.coordinator.applyPresentation(to: view)
        context.coordinator.applyCommand(to: view)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        nsView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        guard let container = nsView.textContainer, let manager = nsView.layoutManager else { return nil }
        manager.ensureLayout(for: container)
        return CGSize(width: width, height: max(44, manager.usedRect(for: container).height))
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BlockNativeEditor
        var lastPublishedText: String
        var commandGate = BlockCommandGate()
        var lastFont: NSFont?
        var lastSpacing: Double?
        var presenting = false
        var presentationDirty = true
        func applyPresentation(to view: NSTextView) {
            guard !view.hasMarkedText() else { return }
            let font = WritingNativePresentation.font(preferences: parent.preferences, kind: parent.kind, headingLevel: parent.headingLevel, rawSourcePresentation: parent.rawSourcePresentation)
            guard presentationDirty || lastFont != font || lastSpacing != parent.preferences.lineSpacing else { return }
            presenting = true
            WritingNativePresentation.apply(to: view, font: font, lineSpacing: parent.preferences.lineSpacing, previousFont: lastFont)
            lastFont = font; lastSpacing = parent.preferences.lineSpacing; presentationDirty = false; presenting = false
        }
        init(_ parent: BlockNativeEditor) { self.parent = parent; lastPublishedText = parent.text }
        func textDidChange(_ notification: Notification) {
            guard !presenting, let view = notification.object as? NSTextView else { return }
            if view.undoManager?.isUndoing == true || view.undoManager?.isRedoing == true { presentationDirty = true }
            applyPresentation(to: view)
            parent.selection = view.selectedRange()
            if !lastPublishedText.utf8.elementsEqual(view.string.utf8) {
                lastPublishedText = view.string; parent.text = view.string
            }
            parent.selectionChanged(view.selectedRange()); view.invalidateIntrinsicContentSize()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !presenting, let view = notification.object as? NSTextView else { return }
            applyPresentation(to: view)
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
            guard let edit = MarkdownLineStyling.applying(command, to: oldSource, selection: projection.isRawSource ? oldSelection : NSRange(location: start, length: end - start)) else { return false }
            guard !edit.source.utf8.elementsEqual(oldSource.utf8) else { return true }
            guard parent.sourceChanged(edit.source) else { return true }
            showSource(edit.source, selection: oldSelection, in: view)
            registerStyleUndo(source: oldSource, selection: oldSelection, inverse: edit.source, inverseSelection: view.selectedRange(), in: view)
            return true
        }
        func showSource(_ source: String, selection: NSRange, in view: NSTextView) {
            let body = BlockProjection(source).text
            if !view.string.utf8.elementsEqual(body.utf8) { view.string = body }
            lastPublishedText = body; presentationDirty = true
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
