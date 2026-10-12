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
    var isEditable = true
    var usesDocumentViewport = false
    let selectionChanged: (NSRange) -> Void
    var selectionRequestGeneration: UInt64 = 0
    let command: BlockEditorCommand?
    let commandHandled: (UUID, Bool) -> Void
    let source: String
    let sourceChanged: (String) -> Bool
    var sourceProvider: (() -> String)? = nil
    var sourceSelectionChanged: ((NSRange) -> Void)? = nil
    var sourceSelectionRequest: NSRange? = nil
    var sourceRejected: ((String) -> Bool)? = nil
    /// Shows the KI menu in the keyboard accessory; nil hides it.
    var onAI: ((BlockAIAction) -> Void)? = nil
    var liveSource: String { sourceProvider?() ?? source }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = FocusRestoringTextView()
        context.coordinator.presenting = true
        defer { context.coordinator.presenting = false }
        view.delegate = context.coordinator
        view.isEditable = isEditable; view.isSelectable = isEditable
        // The inactive row is a concise accessible activation button. Reading
        // and character navigation remain on the active native text editor.
        view.isAccessibilityElement = isEditable
        view.accessibilityElementsHidden = !isEditable
        view.isScrollEnabled = usesDocumentViewport
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityLabel = "\(kind.title) content"
        view.text = text
        context.coordinator.textView = view
        view.inputAccessoryView = context.coordinator.makeAccessory()
        context.coordinator.applyPresentation(to: view)
        view.registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { [weak coordinator = context.coordinator] (view: UITextView, _: UITraitCollection) in
            coordinator?.applyPresentation(to: view)
        }
        view.selectedRange = context.coordinator.initialSelection()
        if isEditable && command == nil { view.requestFocusInWindow() }
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = isEditable; view.isSelectable = isEditable
        view.isAccessibilityElement = isEditable
        view.accessibilityElementsHidden = !isEditable
        view.isScrollEnabled = usesDocumentViewport
        context.coordinator.accessory?.setAIAvailable(onAI != nil)
        context.coordinator.presenting = true
        context.coordinator.synchronize(view)
        context.coordinator.presenting = false
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        if usesDocumentViewport { return CGSize(width: width, height: max(44, proposal.height ?? 480)) }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockNativeEditor
        var lastPublishedText: String
        var inputFrame: BlockInputFrame
        var commandGate = BlockCommandGate()
        var appliedSelectionGeneration: UInt64
        var appliedFocusGeneration: UInt64 = 0
        var lastFont: UIFont?
        var lastSpacing: Double?
        var presenting = false
        var presentationDirty = true
        var sourcePresentationTask: Task<Void, Never>?
        var sourcePresentationGeneration = UUID()
        var requestedPresentationSource: String?
        weak var textView: UITextView?
        weak var accessory: BlockAccessoryBar?
        var inlineTask: Task<Void, Never>?
        var inlineRequestedText: String?
        var inlineStale = true
        var keyboardFrame: CGRect?
        var caretCheckPending = false
        nonisolated(unsafe) var keyboardObserver: NSObjectProtocol?
        deinit {
            sourcePresentationTask?.cancel(); inlineTask?.cancel()
            if let keyboardObserver { NotificationCenter.default.removeObserver(keyboardObserver) }
        }
        func synchronize(_ view: UITextView) {

            // Keep native marked text and cursor intact while a user is composing.
            if view.markedTextRange == nil, !inputFrame.source.utf8.elementsEqual(parent.liveSource.utf8) {
                if !view.text.utf8.elementsEqual(inputFrame.text.utf8),
                   parent.sourceRejected?(inputFrame.draftSource(text: view.text)) != true { return }
                let old = view.selectedRange
                let retained = BlockSelectionUpdate.preservesSourceOffsets(previous: inputFrame.source, accepted: parent.liveSource)
                    ? inputFrame.sourceSelection(old, text: view.text) : nil
                inputFrame.rebase(source: parent.liveSource)
                view.undoManager?.removeAllActions()
                view.text = inputFrame.text
                view.selectedRange = retained.map { inputFrame.bodySelection(forSource: $0) }
                    ?? clamped(old, count: inputFrame.text.utf16.count)
                lastPublishedText = inputFrame.text
                presentationDirty = true
            }
            // Selection is published by native input. Only an explicit newer
            // navigation intent may move it; stale render echoes cannot.
            if view.markedTextRange == nil, parent.selectionRequestGeneration > appliedSelectionGeneration {
                appliedSelectionGeneration = parent.selectionRequestGeneration
                if let sourceRange = parent.sourceSelectionRequest {
                    let start = inputFrame.projection.bodyOffset(forSourceOffset: sourceRange.location, editingText: view.text)
                    let end = inputFrame.projection.bodyOffset(forSourceOffset: sourceRange.location + sourceRange.length, editingText: view.text)
                    view.selectedRange = clamped(NSRange(location: start, length: max(0, end - start)), count: view.text.utf16.count)
                } else { view.selectedRange = clamped(parent.selection, count: view.text.utf16.count) }
                if parent.usesDocumentViewport { view.scrollRangeToVisible(view.selectedRange) }
            }
            if parent.isEditable && parent.selectionRequestGeneration > appliedFocusGeneration {
                appliedFocusGeneration = parent.selectionRequestGeneration
                DispatchQueue.main.async { [weak view] in
                    guard let view, view.isEditable, view.window != nil else { return }
                    view.becomeFirstResponder()
                }
            }
            applyPresentation(to: view)
            applyCommand(to: view)
        }
        func applyPresentation(to view: UITextView) {
            guard view.markedTextRange == nil else { return }
            if inputFrame.projection.isRawSource || (parent.rawSourcePresentation && inputFrame.text.utf8.elementsEqual(inputFrame.source.utf8)) {
                scheduleCompositePresentation(view)
                return
            }
            let kind = inputFrame.styleKind
            let font = WritingNativePresentation.font(preferences: parent.preferences, kind: kind, headingLevel: inputFrame.styleHeadingLevel, rawSourcePresentation: false, traits: view.traitCollection)
            if presentationDirty || lastFont != font || lastSpacing != parent.preferences.lineSpacing {
                presenting = true
                WritingNativePresentation.apply(to: view, font: font, lineSpacing: parent.preferences.lineSpacing, previousFont: lastFont)
                lastFont = font; lastSpacing = parent.preferences.lineSpacing; presentationDirty = false; presenting = false
                inlineStale = true
                restyle(view, runs: [])
            }
            scheduleInlineStyling(view)
        }
        private func scheduleCompositePresentation(_ view: UITextView) {
            let source = view.text ?? ""
            let font = WritingNativePresentation.font(preferences: parent.preferences, kind: .paragraph, traits: view.traitCollection)
            guard presentationDirty || lastFont != font || lastSpacing != parent.preferences.lineSpacing ||
                  !(requestedPresentationSource?.utf8.elementsEqual(source.utf8) ?? false) else { return }
            presentationDirty = false; requestedPresentationSource = source
            lastFont = font; lastSpacing = parent.preferences.lineSpacing
            sourcePresentationTask?.cancel()
            let generation = UUID(); sourcePresentationGeneration = generation
            sourcePresentationTask = Task { @MainActor [weak self, weak view] in
                do {
                    try await Task.sleep(for: .milliseconds(150))
                    let plan = try await MarkdownPresentationWorker.shared.make(source)
                    try Task.checkCancellation()
                    guard let self, let view, self.sourcePresentationGeneration == generation,
                          self.parent.rawSourcePresentation,
                          view.text.utf8.elementsEqual(source.utf8) else { return }
                    guard view.markedTextRange == nil else { self.presentationDirty = true; return }
                    self.presenting = true; defer { self.presenting = false }
                    let selection = view.selectedRange, undo = view.undoManager
                    let registered = undo?.isUndoRegistrationEnabled == true
                    if registered { undo?.disableUndoRegistration() }
                    view.textStorage.beginEditing()
                    let base = WritingNativePresentation.font(preferences: self.parent.preferences, kind: .paragraph, traits: view.traitCollection)
                    let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = self.parent.preferences.lineSpacing
                    view.textStorage.addAttributes([.font: base, .paragraphStyle: paragraph, .foregroundColor: view.textColor ?? UIColor.label], range: NSRange(location: 0, length: view.textStorage.length))
                    for run in plan.runs {
                        switch run.style {
                        case .heading(let level):
                            let heading = WritingNativePresentation.font(preferences: self.parent.preferences, kind: .heading, headingLevel: level, traits: view.traitCollection)
                            view.textStorage.addAttribute(.font, value: heading, range: run.range)
                        case .code:
                            let code = WritingNativePresentation.font(preferences: self.parent.preferences, kind: .code, traits: view.traitCollection)
                            view.textStorage.addAttribute(.font, value: code, range: run.range)
                        case .marker:
                            view.textStorage.addAttribute(.foregroundColor, value: (view.textColor ?? UIColor.label).withAlphaComponent(0.4), range: run.range)
                        case .strong, .emphasis:
                            view.textStorage.enumerateAttribute(.font, in: run.range) { value, range, _ in
                                let current = value as? UIFont ?? base
                                let trait: UIFontDescriptor.SymbolicTraits = run.style == .strong ? .traitBold : .traitItalic
                                let descriptor = current.fontDescriptor.withSymbolicTraits(current.fontDescriptor.symbolicTraits.union(trait)) ?? current.fontDescriptor
                                view.textStorage.addAttribute(.font, value: UIFont(descriptor: descriptor, size: current.pointSize), range: range)
                            }
                        }
                    }
                    view.textStorage.endEditing()
                    if registered { undo?.enableUndoRegistration() }
                    view.selectedRange = selection
                    let caret = min(selection.location, max(0, view.textStorage.length - 1))
                    let typingFont = view.textStorage.length > 0 ? view.textStorage.attribute(.font, at: caret, effectiveRange: nil) as? UIFont ?? base : base
                    view.typingAttributes[.font] = typingFont
                    view.typingAttributes[.paragraphStyle] = paragraph
                    view.invalidateIntrinsicContentSize()
                } catch { /* Cancellation cannot publish an obsolete presentation. */ }
            }
        }
        private static let plainKinds: Set<WritingBlockKind> = [.code, .table, .image]
        func restyle(_ view: UITextView, runs: [MarkdownSourcePresentation.Run]) {
            let kind = inputFrame.styleKind
            let storage = view.textStorage
            guard !Self.plainKinds.contains(kind), view.markedTextRange == nil, storage.length > 0 else { return }
            let preferences = parent.preferences, traits = view.traitCollection
            let body = WritingNativePresentation.font(preferences: preferences, kind: .paragraph, traits: traits)
            let head = WritingNativePresentation.font(preferences: preferences, kind: kind, headingLevel: inputFrame.styleHeadingLevel, traits: traits)
            let color = view.textColor ?? UIColor.label, dim = color.withAlphaComponent(0.4)
            let text = view.text as NSString
            let newline = text.range(of: "\n").location
            let firstLine = kind == .heading ? (newline == NSNotFound ? text.length : newline) : 0
            let wasPresenting = presenting
            presenting = true; defer { presenting = wasPresenting }
            let selection = view.selectedRange, undo = view.undoManager
            let registered = undo?.isUndoRegistrationEnabled == true
            if registered { undo?.disableUndoRegistration() }
            storage.beginEditing()
            storage.addAttributes([.font: body, .foregroundColor: color], range: NSRange(location: 0, length: storage.length))
            if firstLine > 0 { storage.addAttribute(.font, value: head, range: NSRange(location: 0, length: firstLine)) }
            MarkdownInlineStyling.apply(runs, to: storage) { style, existing in
                let current = existing[.font] as? UIFont ?? body
                switch style {
                case .strong: return [.font: current.adding(.traitBold)]
                case .emphasis: return [.font: current.adding(.traitItalic)]
                case .code: return [.font: UIFont.monospacedSystemFont(ofSize: current.pointSize, weight: .regular)]
                case .marker: return [.foregroundColor: dim]
                case .heading: return nil
                }
            }
            storage.endEditing()
            if registered { undo?.enableUndoRegistration() }
            if view.selectedRange != selection { view.selectedRange = selection }
            let at = max(0, min(selection.location, storage.length) - 1)
            let attributes = storage.attributes(at: at, effectiveRange: nil)
            var typing = view.typingAttributes
            let onMarker = (attributes[.foregroundColor] as? UIColor)?.isEqual(dim) == true
            typing[.font] = onMarker ? (at < firstLine ? head : body) : attributes[.font] ?? body
            typing[.foregroundColor] = color
            view.typingAttributes = typing
            view.invalidateIntrinsicContentSize()
        }
        /// Emphasis and marker styling follows typing after a short pause; the text itself is never touched.
        func scheduleInlineStyling(_ view: UITextView) {
            guard !Self.plainKinds.contains(inputFrame.styleKind) else { inlineTask?.cancel(); return }
            let text = view.text ?? ""
            if !inlineStale, inlineRequestedText?.utf8.elementsEqual(text.utf8) == true { return }
            inlineStale = false; inlineRequestedText = text
            inlineTask?.cancel()
            inlineTask = Task { @MainActor [weak self, weak view] in
                do {
                    try await Task.sleep(for: .milliseconds(150))
                    let plan = try await MarkdownPresentationWorker.shared.make(text)
                    try Task.checkCancellation()
                    guard let self, let view, view.text.utf8.elementsEqual(text.utf8) else { return }
                    guard view.markedTextRange == nil else { self.inlineRequestedText = nil; return }
                    self.restyle(view, runs: plan.runs)
                } catch { /* A newer edit owns the presentation. */ }
            }
        }
        init(_ parent: BlockNativeEditor) { self.parent = parent; inputFrame = BlockInputFrame(source: parent.liveSource); lastPublishedText = inputFrame.text; appliedSelectionGeneration = parent.selectionRequestGeneration }
        func initialSelection() -> NSRange {
            if let sourceRange = parent.sourceSelectionRequest {
                return inputFrame.bodySelection(forSource: sourceRange)
            }
            return clamped(parent.selection, count: inputFrame.text.utf16.count)
        }
        func textViewDidChange(_ view: UITextView) {
            guard !presenting else { return }

            if view.undoManager?.isUndoing == true || view.undoManager?.isRedoing == true { presentationDirty = true }
            applyPresentation(to: view)
            if !lastPublishedText.utf8.elementsEqual(view.text.utf8) {
                let buffer = view.text ?? ""
                guard let candidate = inputFrame.proposedSource(text: buffer, canonical: parent.liveSource) else {
                    _ = parent.sourceRejected?(inputFrame.draftSource(text: buffer)); return
                }
                guard parent.sourceChanged(candidate) else {
                    _ = parent.sourceRejected?(candidate); return
                }
                if parent.liveSource.utf8.elementsEqual(candidate.utf8) { inputFrame.accept(text: buffer, source: candidate) }
                else { inputFrame.rebase(source: parent.liveSource); view.text = inputFrame.text }
                lastPublishedText = inputFrame.text
                applyPresentation(to: view)
            }
            publishSelection(view)
            view.invalidateIntrinsicContentSize()
            refreshAccessory(view); scheduleCaretCheck(view)
        }
        func textViewDidChangeSelection(_ view: UITextView) {
            guard !presenting else { return }
            applyPresentation(to: view)
            publishSelection(view)
            refreshAccessory(view); scheduleCaretCheck(view)
        }
        func publishSelection(_ view: UITextView) {
            parent.selection = view.selectedRange
            let sourceRange = inputFrame.sourceSelection(view.selectedRange, text: view.text ?? "")
            if let notify = parent.sourceSelectionChanged { notify(sourceRange) }
            else {
                let projection = BlockProjection(parent.liveSource)
                let start = projection.bodyOffset(forSourceOffset: sourceRange.location)
                let end = projection.bodyOffset(forSourceOffset: sourceRange.location + sourceRange.length)
                parent.selectionChanged(NSRange(location: start, length: max(0, end - start)))
            }
        }
        func applyCommand(to view: UITextView) {
            guard let command = parent.command, commandGate.claim(command.id) else { return }
            guard view.isFirstResponder else {
                DispatchQueue.main.async { self.parent.commandHandled(command.id, false) }
                return
            }
            DispatchQueue.main.async {
                guard self.parent.command?.id == command.id else { return }
                guard view.window != nil, view.isFirstResponder else {
                    self.parent.commandHandled(command.id, false); return
                }
                self.parent.commandHandled(command.id, self.perform(command, on: view))
            }
        }
        @discardableResult func perform(_ command: BlockEditorCommand, on view: UITextView) -> Bool {
            guard view.markedTextRange == nil,
                let edit = BlockCommandEditing.applying(command, to: view.text, selection: view.selectedRange) else { return false }
            if command.isLineStyle { return applyStyle(command, to: view) }
            let undo = view.undoManager
            undo?.beginUndoGrouping()
            view.selectedRange = edit.replacementRange
            // UITextInput's normal insertion path registers a native undo.
            view.insertText(edit.replacement)
            let isLink = command.prefix == "[" && command.suffix.hasPrefix("](")
            view.selectedRange = isLink ? BlockEditorCommand.linkURLSelection(afterReplacing: edit.replacementRange) : edit.selection
            textViewDidChange(view)
            undo?.setActionName("Formatieren")
            undo?.endUndoGrouping()
            return true
        }
        func makeAccessory() -> BlockAccessoryBar {
            let bar = BlockAccessoryBar(actions: .init(
                bold: { [weak self] in self?.accessoryCommand(.bold) },
                italic: { [weak self] in self?.accessoryCommand(.italic) },
                heading: { [weak self] in self?.accessoryHeading() },
                list: { [weak self] in self?.accessoryList() },
                link: { [weak self] in self?.accessoryCommand(.link) },
                undo: { [weak self] in self?.textView?.undoManager?.undo(); self?.afterUndoRedo() },
                redo: { [weak self] in self?.textView?.undoManager?.redo(); self?.afterUndoRedo() },
                ai: { [weak self] action in self?.parent.onAI?(action) },
                dismiss: { [weak self] in self?.textView?.resignFirstResponder() }))
            bar.setAIAvailable(parent.onAI != nil)
            accessory = bar
            keyboardObserver = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
                let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                MainActor.assumeIsolated {
                    guard let self, let view = self.textView, view.isFirstResponder else { return }
                    self.keyboardFrame = frame
                    self.ensureCaretVisible(view)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak view] in if let self, let view { self.ensureCaretVisible(view) } }
                }
            }
            return bar
        }
        private func accessoryCommand(_ command: @autoclosure () -> BlockEditorCommand) {
            guard let view = textView, view.isFirstResponder else { return }
            perform(command(), on: view)
        }
        private func accessoryHeading() {
            guard let view = textView, view.isFirstResponder else { return }
            let kind = inputFrame.styleKind
            if inputFrame.projection.isRawSource {
                let text = view.text as NSString
                let line = text.substring(with: text.lineRange(for: NSRange(location: min(view.selectedRange.location, text.length), length: 0)))
                perform(.heading(after: line.prefix(while: { $0 == "#" }).count), on: view)
            } else if kind == .paragraph || kind == .heading {
                perform(.heading(after: kind == .heading ? inputFrame.styleHeadingLevel : 0), on: view)
            }
        }
        private func accessoryList() {
            guard let view = textView, view.isFirstResponder else { return }
            let remove = inputFrame.styleKind == .list && !inputFrame.projection.isRawSource
            perform(remove ? BlockEditorCommand(prefix: "", suffix: "") : .list, on: view)
        }
        private func afterUndoRedo() {
            guard let view = textView else { return }
            presentationDirty = true; inlineStale = true
            refreshAccessory(view)
        }
        func refreshAccessory(_ view: UITextView) {
            accessory?.setUndo(canUndo: view.undoManager?.canUndo == true, canRedo: view.undoManager?.canRedo == true)
        }
        func scheduleCaretCheck(_ view: UITextView) {
            guard !view.isScrollEnabled, view.isFirstResponder, !caretCheckPending else { return }
            caretCheckPending = true
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self else { return }
                self.caretCheckPending = false
                if let view { self.ensureCaretVisible(view) }
            }
        }
        /// Scrolls the enclosing page so the caret clears keyboard and accessory bar.
        func ensureCaretVisible(_ view: UITextView) {
            guard view.isFirstResponder, !view.isScrollEnabled, let window = view.window, let end = view.selectedTextRange?.end else { return }
            var ancestor = view.superview
            while let candidate = ancestor, (candidate as? UIScrollView)?.isScrollEnabled != true { ancestor = candidate.superview }
            guard let scroll = ancestor as? UIScrollView else { return }
            let space = window.screen.coordinateSpace
            let keyboardTop = keyboardFrame.map { space.convert($0, to: window).minY }
            var accessoryTop: CGFloat?
            if let bar = accessory, let barWindow = bar.window {
                accessoryTop = space.convert(bar.convert(bar.bounds, to: barWindow.screen.coordinateSpace), to: window).minY
            }
            guard let obscured = CaretVisibility.obscuredTop(keyboardTop: keyboardTop, accessoryTop: accessoryTop) else { return }
            let caret = view.convert(view.caretRect(for: end), to: window)
            let frame = scroll.convert(scroll.bounds, to: window)
            let inset = scroll.adjustedContentInset
            let delta = CaretVisibility.offsetDelta(caret: caret, visibleTop: frame.minY + inset.top, obscuredTop: obscured, margin: 12)
            guard abs(delta) > 0.5 else { return }
            let overlap = max(0, frame.maxY - obscured)
            let y = CaretVisibility.clampedOffset(current: scroll.contentOffset.y, delta: delta, minimum: -inset.top,
                maximum: scroll.contentSize.height - scroll.bounds.height + inset.bottom + overlap)
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: true)
        }
        func applyStyle(_ command: BlockEditorCommand, to view: UITextView) -> Bool {
            guard ![WritingBlockKind.code, .image, .table].contains(parent.kind) else { return false }
            let oldSource = parent.liveSource, oldSelection = view.selectedRange
            guard oldSource.utf8.elementsEqual(inputFrame.source.utf8) else { return false }
            let scope = inputFrame.projection.isRawSource ? oldSelection : NSRange(location: 0, length: view.text.utf16.count)
            guard let edit = MarkdownLineStyling.applying(command, to: oldSource, selection: inputFrame.sourceSelection(scope, text: view.text)) else { return false }
            guard !edit.source.utf8.elementsEqual(oldSource.utf8) else { return true }
            guard parent.sourceChanged(edit.source) else { return true }
            showSource(edit.source, selection: oldSelection, in: view)
            registerStyleUndo(source: oldSource, selection: oldSelection, inverse: edit.source, inverseSelection: view.selectedRange, in: view)
            return true
        }
        func showSource(_ source: String, selection: NSRange, in view: UITextView) {
            inputFrame.rebase(source: source)
            let body = inputFrame.text
            if !view.text.utf8.elementsEqual(body.utf8) { view.text = body }
            lastPublishedText = body; presentationDirty = true
            view.selectedRange = clamped(selection, count: body.utf16.count)
            publishSelection(view)
        }
        func registerStyleUndo(source: String, selection: NSRange, inverse: String, inverseSelection: NSRange, in view: UITextView) {
            view.undoManager?.registerUndo(withTarget: self) { [weak view] coordinator in
                MainActor.assumeIsolated {
                    guard let view else { return }
                    guard coordinator.parent.liveSource.utf8.elementsEqual(inverse.utf8) else {
                        _ = coordinator.parent.sourceRejected?(source); return
                    }
                    guard coordinator.parent.sourceChanged(source) else {
                        _ = coordinator.parent.sourceRejected?(source); return
                    }
                    coordinator.showSource(source, selection: selection, in: view)
                    coordinator.registerStyleUndo(source: inverse, selection: inverseSelection, inverse: source, inverseSelection: selection, in: view)
                }
            }
            view.undoManager?.setActionName("Blockstil")
        }
    }
}
/// Formatting strip above the software keyboard. Plain UIKit, so the text view keeps first responder status.
@MainActor final class BlockAccessoryBar: UIInputView {
    struct Actions {
        var bold, italic, heading, list, link, undo, redo: () -> Void
        var ai: (BlockAIAction) -> Void
        var dismiss: () -> Void
    }
    static let height: CGFloat = 44
    private let undoButton: UIButton, redoButton: UIButton, aiButton: UIButton

    private static func button(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.accessibilityLabel = label
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: height).isActive = true
        return button
    }

    init(actions: Actions) {
        undoButton = Self.button("arrow.uturn.backward", "Rückgängig", actions.undo)
        redoButton = Self.button("arrow.uturn.forward", "Wiederholen", actions.redo)
        aiButton = Self.button("sparkles", "KI-Aktionen", {})
        aiButton.menu = UIMenu(children: BlockAIAction.allCases.map { action in UIAction(title: action.title) { _ in actions.ai(action) } })
        aiButton.showsMenuAsPrimaryAction = true
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: Self.height), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        let stack = UIStackView(arrangedSubviews: [
            Self.button("bold", "Fett", actions.bold), Self.button("italic", "Kursiv", actions.italic),
            Self.button("textformat.size", "Überschrift wechseln", actions.heading), Self.button("list.bullet", "Liste", actions.list),
            Self.button("link", "Link", actions.link), undoButton, redoButton, aiButton])
        stack.axis = .horizontal; stack.spacing = 2; stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false; scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        let dismiss = Self.button("keyboard.chevron.compact.down", "Tastatur schließen", actions.dismiss)
        dismiss.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll); addSubview(dismiss)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.trailingAnchor.constraint(equalTo: dismiss.leadingAnchor),
            dismiss.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            dismiss.topAnchor.constraint(equalTo: topAnchor), dismiss.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)])
        setUndo(canUndo: false, canRedo: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.height) }
    func setAIAvailable(_ available: Bool) { aiButton.isHidden = !available }
    func setUndo(canUndo: Bool, canRedo: Bool) { undoButton.isEnabled = canUndo; redoButton.isEnabled = canRedo }
}

private extension UIFont {
    func adding(_ trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        UIFont(descriptor: fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(trait)) ?? fontDescriptor, size: pointSize)
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
    var isEditable = true
    var usesDocumentViewport = false
    let selectionChanged: (NSRange) -> Void
    var selectionRequestGeneration: UInt64 = 0
    let command: BlockEditorCommand?
    let commandHandled: (UUID, Bool) -> Void
    let source: String
    let sourceChanged: (String) -> Bool
    var sourceProvider: (() -> String)? = nil
    var sourceSelectionChanged: ((NSRange) -> Void)? = nil
    var sourceSelectionRequest: NSRange? = nil
    var sourceRejected: ((String) -> Bool)? = nil
    var onAI: ((BlockAIAction) -> Void)? = nil
    var liveSource: String { sourceProvider?() ?? source }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.delegate = context.coordinator
        view.isRichText = false; view.drawsBackground = false; view.allowsUndo = true
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.textContainerInset = .zero; view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.string = text; context.coordinator.applyPresentation(to: view)
        view.setSelectedRange(context.coordinator.initialSelection())
        view.setAccessibilityLabel("\(kind.title) content")
        if command == nil { DispatchQueue.main.async { view.window?.makeFirstResponder(view) } }
        return view
    }
    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.synchronize(view)
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
        var inputFrame: BlockInputFrame
        var commandGate = BlockCommandGate()
        var appliedSelectionGeneration: UInt64
        var lastFont: NSFont?
        var lastSpacing: Double?
        var presenting = false
        var presentationDirty = true
        func synchronize(_ view: NSTextView) {
            if !view.hasMarkedText(), !inputFrame.source.utf8.elementsEqual(parent.liveSource.utf8) {
                if !view.string.utf8.elementsEqual(inputFrame.text.utf8),
                   parent.sourceRejected?(inputFrame.draftSource(text: view.string)) != true { return }
                let old = view.selectedRange()
                let retained = BlockSelectionUpdate.preservesSourceOffsets(previous: inputFrame.source, accepted: parent.liveSource)
                    ? inputFrame.sourceSelection(old, text: view.string) : nil
                inputFrame.rebase(source: parent.liveSource)
                view.undoManager?.removeAllActions()
                view.string = inputFrame.text
                view.setSelectedRange(retained.map { inputFrame.bodySelection(forSource: $0) }
                    ?? clamped(old, count: inputFrame.text.utf16.count))
                lastPublishedText = inputFrame.text
                presentationDirty = true
            }
            if !view.hasMarkedText(), parent.selectionRequestGeneration > appliedSelectionGeneration {
                appliedSelectionGeneration = parent.selectionRequestGeneration
                if let sourceRange = parent.sourceSelectionRequest {
                    let start = inputFrame.projection.bodyOffset(forSourceOffset: sourceRange.location, editingText: view.string)
                    let end = inputFrame.projection.bodyOffset(forSourceOffset: sourceRange.location + sourceRange.length, editingText: view.string)
                    view.setSelectedRange(clamped(NSRange(location: start, length: max(0, end - start)), count: view.string.utf16.count))
                } else { view.setSelectedRange(clamped(parent.selection, count: view.string.utf16.count)) }
            }
            applyPresentation(to: view)
            applyCommand(to: view)
        }
        func applyPresentation(to view: NSTextView) {
            guard !view.hasMarkedText() else { return }
            let font = WritingNativePresentation.font(preferences: parent.preferences, kind: inputFrame.projection.kind, headingLevel: inputFrame.projection.headingLevel, rawSourcePresentation: inputFrame.projection.isRawSource)
            guard presentationDirty || lastFont != font || lastSpacing != parent.preferences.lineSpacing else { return }
            presenting = true
            WritingNativePresentation.apply(to: view, font: font, lineSpacing: parent.preferences.lineSpacing, previousFont: lastFont)
            lastFont = font; lastSpacing = parent.preferences.lineSpacing; presentationDirty = false; presenting = false
        }
        init(_ parent: BlockNativeEditor) { self.parent = parent; inputFrame = BlockInputFrame(source: parent.liveSource); lastPublishedText = inputFrame.text; appliedSelectionGeneration = parent.selectionRequestGeneration }
        func initialSelection() -> NSRange {
            if let sourceRange = parent.sourceSelectionRequest {
                return inputFrame.bodySelection(forSource: sourceRange)
            }
            return clamped(parent.selection, count: inputFrame.text.utf16.count)
        }
        func textDidChange(_ notification: Notification) {
            guard !presenting, let view = notification.object as? NSTextView else { return }
            if view.undoManager?.isUndoing == true || view.undoManager?.isRedoing == true { presentationDirty = true }
            applyPresentation(to: view)
            if !lastPublishedText.utf8.elementsEqual(view.string.utf8) {
                let buffer = view.string
                guard let candidate = inputFrame.proposedSource(text: buffer, canonical: parent.liveSource) else {
                    _ = parent.sourceRejected?(inputFrame.draftSource(text: buffer)); return
                }
                guard parent.sourceChanged(candidate) else { _ = parent.sourceRejected?(candidate); return }
                if parent.liveSource.utf8.elementsEqual(candidate.utf8) { inputFrame.accept(text: buffer, source: candidate) }
                else { inputFrame.rebase(source: parent.liveSource); view.string = inputFrame.text }
                lastPublishedText = inputFrame.text
            }
            publishSelection(view); view.invalidateIntrinsicContentSize()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !presenting, let view = notification.object as? NSTextView else { return }
            applyPresentation(to: view)
            publishSelection(view)
        }
        func publishSelection(_ view: NSTextView) {
            parent.selection = view.selectedRange()
            let sourceRange = inputFrame.sourceSelection(view.selectedRange(), text: view.string)
            if let notify = parent.sourceSelectionChanged { notify(sourceRange) }
            else {
                let projection = BlockProjection(parent.liveSource)
                let start = projection.bodyOffset(forSourceOffset: sourceRange.location)
                let end = projection.bodyOffset(forSourceOffset: sourceRange.location + sourceRange.length)
                parent.selectionChanged(NSRange(location: start, length: max(0, end - start)))
            }
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
            let oldSource = parent.liveSource, oldSelection = view.selectedRange()
            guard oldSource.utf8.elementsEqual(inputFrame.source.utf8) else { return false }
            let scope = inputFrame.projection.isRawSource ? oldSelection : NSRange(location: 0, length: view.string.utf16.count)
            guard let edit = MarkdownLineStyling.applying(command, to: oldSource, selection: inputFrame.sourceSelection(scope, text: view.string)) else { return false }
            guard !edit.source.utf8.elementsEqual(oldSource.utf8) else { return true }
            guard parent.sourceChanged(edit.source) else { return true }
            showSource(edit.source, selection: oldSelection, in: view)
            registerStyleUndo(source: oldSource, selection: oldSelection, inverse: edit.source, inverseSelection: view.selectedRange(), in: view)
            return true
        }
        func showSource(_ source: String, selection: NSRange, in view: NSTextView) {
            inputFrame.rebase(source: source)
            let body = inputFrame.text
            if !view.string.utf8.elementsEqual(body.utf8) { view.string = body }
            lastPublishedText = body; presentationDirty = true
            view.setSelectedRange(clamped(selection, count: body.utf16.count))
            publishSelection(view)
        }
        func registerStyleUndo(source: String, selection: NSRange, inverse: String, inverseSelection: NSRange, in view: NSTextView) {
            view.undoManager?.registerUndo(withTarget: self) { [weak view] coordinator in
                MainActor.assumeIsolated {
                    guard let view else { return }
                    guard coordinator.parent.liveSource.utf8.elementsEqual(inverse.utf8) else {
                        _ = coordinator.parent.sourceRejected?(source); return
                    }
                    guard coordinator.parent.sourceChanged(source) else {
                        _ = coordinator.parent.sourceRejected?(source); return
                    }
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
