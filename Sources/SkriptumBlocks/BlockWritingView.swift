import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
#if canImport(SkriptumCore)
import SkriptumCore
#endif

/// Pages-style editing with one live TextKit view and lazy, semantic block rows.
public struct BlockWritingView: View {
    @Binding private var markdown: String
    @Binding private var selection: NSRange
    private var preferences: WritingPreferences
    private var onPageReference: (() -> String?)?
    private var onPrompt: (() -> Void)?
    private var initialBlocks: [Block]?
    private var onBlocksChanged: (([Block]) -> Bool)?
    private var onTable: ((UUID) -> Void)?
    private var onImage: ((UUID?) -> Void)?
    private var imageData: ((String) -> Data?)?
    private var command: BlockEditorCommand?
    private var onCommandHandled: (() -> Void)?
    private var onCommandUnavailable: (() -> Void)?
    private var jumpToUTF16: Int?
    private var onJumpHandled: (() -> Void)?
    @State private var blocks: [Block]
    @State private var activeID: UUID?
    @State private var slashID: UUID?
    @State private var slashPresented = false
    @State private var editorSelection = NSRange(location: 0, length: 0)
    @State private var editorReset = 0
    @State private var commandGate = BlockCommandGate()

    public init(markdown: Binding<String>, selection: Binding<NSRange>, initialBlocks: [Block]? = nil, preferences: WritingPreferences = .standard, onBlocksChanged: (([Block]) -> Bool)? = nil, onPageReference: (() -> String?)? = nil, onPrompt: (() -> Void)? = nil, onImage: ((UUID?) -> Void)? = nil, onTable: ((UUID) -> Void)? = nil, imageData: ((String) -> Data?)? = nil, command: BlockEditorCommand? = nil, onCommandHandled: (() -> Void)? = nil, jumpToUTF16: Int? = nil, onJumpHandled: (() -> Void)? = nil, onCommandUnavailable: (() -> Void)? = nil) {
        _markdown = markdown; _selection = selection; self.preferences = preferences
        self.onPageReference = onPageReference; self.onPrompt = onPrompt
        self.initialBlocks = initialBlocks; self.onBlocksChanged = onBlocksChanged
        self.onImage = onImage; self.onTable = onTable; self.imageData = imageData
        self.command = command; self.onCommandHandled = onCommandHandled
        self.jumpToUTF16 = jumpToUTF16; self.onJumpHandled = onJumpHandled
        self.onCommandUnavailable = onCommandUnavailable
        _blocks = State(initialValue: BlockEditing.initialBlocks(markdown: markdown.wrappedValue, stored: initialBlocks))
    }

    public var body: some View {
        ScrollViewReader { proxy in
        VStack(spacing: 0) {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(blocks) { block in
                    WritingBlockRow(block: block, currentSource: { blocks.first(where: { $0.id == block.id })?.markdown ?? block.markdown }, preferences: preferences, active: activeID == block.id, editorReset: editorReset, imageData: imageData, command: activeID == block.id ? command : nil, commandHandled: completeCommand, localSelection: $editorSelection,
                        activate: { activate(block) }, edit: { text in edit(block.id, text: text) },
                        sourceEdited: { source in commit(BlockEditing.replacingMarkdown(blocks, id: block.id, markdown: source)) },
                        selectionChanged: { range in updateSelection(block.id, range: range) },
                        insert: { presentInsertion(after: block.id) },
                        move: { _ = commit(BlockEditing.moving(blocks, id: block.id, direction: $0)) },
                        duplicate: { _ = commit(BlockEditing.duplicating(blocks, id: block.id)) },
                        delete: { if commit(BlockEditing.deleting(blocks, id: block.id)), activeID == block.id { activeID = nil } },
                        table: onTable == nil ? nil : { activeID = nil; onTable?(block.id) },
                        toggleTask: { line in _ = commit(BlockEditing.togglingTask(blocks, id: block.id, line: line)) })
                        .id(block.id)
                        .dropDestination(for: String.self) { values, _ in
                            guard let value = values.first, let id = UUID(uuidString: value), blocks.contains(where: { $0.id == id }) else { return false }
                            return commit(BlockEditing.moving(blocks, id: id, before: block.id))
                        }
                }
                Button { presentInsertion(after: blocks.last?.id) } label: {
                    Label("Block hinzufügen", systemImage: "plus.circle").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityHint("Blocktyp wählen")
            }.padding(.horizontal, 20).padding(.vertical, 28).frame(maxWidth: preferences.contentWidth.map { CGFloat($0) } ?? .infinity).frame(maxWidth: .infinity)
        }
        if slashPresented { insertionPalette }
        }
        .accessibilityIdentifier("blockWritingView")
        .onChange(of: markdown) { _, value in
            guard !value.utf8.elementsEqual(blocks.map(\.markdown).joined().utf8) else { return }
            blocks = BlockEditing.initialBlocks(markdown: value, stored: initialBlocks ?? blocks)
            if let activeID, !blocks.contains(where: { $0.id == activeID }) { self.activeID = nil }
        }
        .onChange(of: initialBlocks) { _, value in
            guard let value, value.map(\.markdown).joined().utf8.elementsEqual(markdown.utf8) else { return }
            blocks = value
            if let activeID, !blocks.contains(where: { $0.id == activeID }) { self.activeID = nil }
        }
        .task(id: command?.id) {
            guard let command else { return }
            guard let activeID, blocks.contains(where: { $0.id == activeID }) else {
                completeCommand(command.id, false); return
            }
            proxy.scrollTo(activeID, anchor: .center)
        }
        .task(id: jumpToUTF16) {
            guard let offset = jumpToUTF16 else { return }
            if let target = BlockCommandEditing.caretTarget(in: blocks, sourceOffset: offset) {
                slashPresented = false
                editorSelection = target.selection
                activeID = target.blockID
                updateSelection(target.blockID, range: target.selection)
                proxy.scrollTo(target.blockID, anchor: .center)
            }
            onJumpHandled?()
        }
        }
    }

    private func completeCommand(_ id: UUID, _ available: Bool) {
        guard commandGate.claim(id) else { return }
        if !available { onCommandUnavailable?() }
        onCommandHandled?()
    }

    /// Owned by the editor's layout rather than a nested presentation host.
    /// It remains usable while the enclosing document is itself presented.
    private var insertionPalette: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Block einfügen").font(.headline)
                Spacer()
                Button("Abbrechen", systemImage: "xmark") { slashPresented = false }
                    .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Blockauswahl schließen")
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    ForEach(WritingBlockKind.allCases) { kind in
                        Button {
                            if kind == .image { slashPresented = false; onImage?(slashID) }
                            else { insert(kind.template) }
                        } label: {
                            Label(kind.title, systemImage: insertionIcon(kind))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.buttonStyle(.bordered)
                            .disabled(kind == .image && onImage == nil)
                            .accessibilityIdentifier("insertBlock-\(kind.rawValue)")
                    }
                    Button {
                        slashPresented = false
                        if let reference = onPageReference?() { insert(reference + "\n\n") }
                    } label: {
                        Label("Seitenverweis", systemImage: "link").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.bordered).disabled(onPageReference == nil)
                    Button { slashPresented = false; onPrompt?() } label: {
                        Label("Prompt", systemImage: "sparkles").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.bordered).disabled(onPrompt == nil)
                }
            }.frame(maxHeight: 260)
        }.padding(.horizontal, 20).padding(.bottom, 12)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
            .accessibilityIdentifier("blockInsertionPalette")
    }

    private func insertionIcon(_ kind: WritingBlockKind) -> String {
        switch kind {
        case .paragraph: return "text.alignleft"
        case .heading: return "textformat.size"
        case .list: return "list.bullet"
        case .checklist: return "checklist"
        case .quote: return "text.quote"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .table: return "tablecells"
        case .image: return "photo"
        }
    }

    private func presentInsertion(after id: UUID?) {
        activeID = nil
        slashID = id
        slashPresented = true
    }

    private func activate(_ block: Block) {
        editorSelection = NSRange(location: BlockProjection(block.markdown).text.utf16.count, length: 0)
        activeID = block.id; updateSelection(block.id, range: editorSelection)
    }
    private func edit(_ id: UUID, text: String) {
        // A slash on an otherwise empty block is a command; it never becomes
        // hidden document syntax. Escape/Cancel keeps the original empty block.
        if text == "/", let block = blocks.first(where: { $0.id == id }), BlockProjection(block.markdown).text.isEmpty {
            presentInsertion(after: id); return
        }
        if !commit(BlockEditing.replacing(blocks, id: id, text: text)) { editorReset += 1 }
    }
    @discardableResult private func commit(_ value: [Block]) -> Bool {
        // Publish domain identity first: the owner can store reordered blocks
        // atomically instead of re-deriving their IDs from the Markdown string.
        guard let accepted = BlockEditing.acceptedProposal(value, accept: onBlocksChanged) else { return false }
        blocks = accepted
        let source = accepted.map(\.markdown).joined()
        if !markdown.utf8.elementsEqual(source.utf8) { markdown = source }
        if let activeID { updateSelection(activeID, range: editorSelection) }
        return true
    }
    private func updateSelection(_ id: UUID, range: NSRange) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let projection = BlockProjection(blocks[index].markdown)
        let start = projection.sourceOffset(for: range.location)
        let end = projection.sourceOffset(for: range.location + range.length)
        selection = NSRange(location: blocks.prefix(index).reduce(0) { $0 + $1.markdown.utf16.count } + start, length: max(0, end - start))
    }
    private func insert(_ source: String) {
        let oldIDs = Set(blocks.map(\.id))
        let result = BlockEditing.inserting(blocks, after: slashID, markdown: source)
        guard commit(result) else { return }
        slashPresented = false
        if let inserted = result.first(where: { candidate in !oldIDs.contains(candidate.id) }) { activate(inserted) }
    }
}

private struct WritingBlockRow: View {
    let block: Block
    let currentSource: () -> String
    let preferences: WritingPreferences
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17
    @ScaledMetric(relativeTo: .largeTitle) private var largeSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 28
    @ScaledMetric(relativeTo: .title3) private var headingSize: CGFloat = 20
    let active: Bool
    let editorReset: Int
    let imageData: ((String) -> Data?)?
    let command: BlockEditorCommand?
    let commandHandled: (UUID, Bool) -> Void
    @Binding var localSelection: NSRange
    let activate: () -> Void
    let edit: (String) -> Void
    let sourceEdited: (String) -> Bool
    let selectionChanged: (NSRange) -> Void
    let insert: () -> Void
    let move: (Int) -> Void
    let duplicate: () -> Void
    let delete: () -> Void
    let table: (() -> Void)?
    let toggleTask: (Int) -> Void
    @State private var taskRows: [Block] = []
    private var projection: BlockProjection { BlockProjection(block.markdown) }
    private var font: Font {
        let design: Font.Design
        switch preferences.fontDesign {
        case .system: design = .default
        case .serif: design = .serif
        case .rounded: design = .rounded
        case .monospaced: design = .monospaced
        }
        let heading = projection.kind == .heading && !projection.isRawSource
        let size = heading ? (projection.headingLevel <= 1 ? largeSize : (projection.headingLevel == 2 ? titleSize : headingSize)) : bodySize
        return .system(size: size * preferences.fontScale, weight: heading ? .bold : .regular,
            design: projection.isRawSource || projection.kind == .code || projection.kind == .table ? .monospaced : design)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Menu {
                if projection.kind == .table, (try? MarkdownTable(block.markdown)) != nil, let table {
                    Button("Tabelle bearbeiten", systemImage: "tablecells", action: table)
                }
                Button("Insert after", systemImage: "plus", action: insert)
                Button("Nach oben", systemImage: "arrow.up") { move(-1) }
                Button("Nach unten", systemImage: "arrow.down") { move(1) }
                Button("Duplizieren", systemImage: "plus.square.on.square", action: duplicate)
                Button("Delete block", systemImage: "trash", role: .destructive, action: delete)
            } label: {
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).frame(width: 32, height: 44)
            }.draggable(block.id.uuidString)
                .accessibilityLabel("\(projection.kind.title) block actions")
                .accessibilityHint("Open menu, or drag to reorder")
            VStack(alignment: .leading, spacing: 6) {
                if projection.isRawSource { Text("Markdown-Quelltext").font(.caption).foregroundStyle(.secondary)
                    .accessibilityHint("Dieser Block enthält mehrere Markdown-Abschnitte. Der vollständige Quelltext bleibt erhalten.") }
                if projection.kind == .table { Text("Markdown table").font(.caption).foregroundStyle(.secondary) }
                if active {
                    BlockNativeEditor(text: BlockEditorBinding.text(readSource: currentSource, writeText: edit), selection: $localSelection,
                        kind: projection.kind, headingLevel: projection.headingLevel, preferences: preferences, rawSourcePresentation: projection.isRawSource, selectionChanged: selectionChanged,
                        command: command, commandHandled: commandHandled, source: block.markdown, sourceChanged: sourceEdited, sourceProvider: currentSource)
                        .id(editorReset)
                        .frame(minHeight: 44)
                } else {
                    semanticText
                        .lineSpacing(preferences.lineSpacing)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle()).onTapGesture(perform: activate)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(accessibleContent)
                        .accessibilityHint("Double tap to edit \(projection.kind.title.lowercased())")
                        .accessibilityAction(named: "Edit", activate)
                }
            }.padding(.vertical, projection.kind == .code ? 12 : 0)
                .padding(.horizontal, projection.kind == .code ? 12 : 0)
                .background(projection.kind == .code ? Color.secondary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        }.frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { refreshTasks() }
            .onChange(of: block.markdown) { _, _ in refreshTasks() }
    }
    private var accessibleContent: String {
        if let image = BlockImageReference(block.markdown) { return image.altText.isEmpty ? "Bild" : image.altText }
        return projection.text.isEmpty ? "Empty paragraph" : projection.text
    }
    @ViewBuilder private var semanticText: some View {
        switch projection.kind {
        case .image:
            if let reference = BlockImageReference(block.markdown) {
                WritingImageBlock(reference: reference, data: imageData?(reference.target))
            }
        case .checklist:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(taskRows) { task in
                    let checked = task.markdown.range(of: "\\[[xX]\\]", options: .regularExpression) != nil
                    HStack(alignment: .top, spacing: 8) {
                        Button {
                            if let index = taskRows.firstIndex(where: { $0.id == task.id }) { toggleTask(index) }
                        } label: { Image(systemName: checked ? "checkmark.square.fill" : "square").frame(width: 28, height: 28) }
                            .buttonStyle(.plain).accessibilityLabel(checked ? "Mark task incomplete" : "Complete task")
                        Text(BlockProjection(task.markdown).text).font(font).strikethrough(checked).onTapGesture(perform: activate)
                    }
                }
            }
        case .list:
            Text(listDisplay).font(font)
        case .quote:
            HStack(alignment: .top) { Rectangle().fill(.secondary.opacity(0.4)).frame(width: 3); Text(projection.text).font(font).italic() }.fixedSize(horizontal: false, vertical: true)
        default:
            Text(projection.text.isEmpty ? "Tap to write…" : projection.text).font(font)
                .foregroundStyle(projection.text.isEmpty ? .secondary : .primary)
        }
    }
    private func refreshTasks() {
        guard projection.kind == .checklist else { taskRows = []; return }
        let count = projection.text.components(separatedBy: "\n").count
        let source = block.markdown.components(separatedBy: "\n").prefix(count).map { $0 + "\n\n" }.joined()
        taskRows = MarkdownReconciler.reconcile(source, previous: taskRows)
    }
    private var listDisplay: String {
        let sourceLines = block.markdown.components(separatedBy: "\n")
        return projection.text.components(separatedBy: "\n").enumerated().map { index, line in
            if projection.kind == .checklist {
                let checked = index < sourceLines.count && sourceLines[index].range(of: "\\[[xX]\\]", options: .regularExpression) != nil
                return (checked ? "☑ " : "☐ ") + line
            }
            return "• " + line
        }.joined(separator: "\n")
    }
}

private struct WritingImageBlock: View {
    let reference: BlockImageReference
    let data: Data?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = raster {
                image.resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 340)
                    .accessibilityLabel(reference.altText.isEmpty ? "Bild" : reference.altText)
            } else {
                Label("Bild nicht verfügbar", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary).frame(minHeight: 80)
            }
            if !reference.altText.isEmpty { Text(reference.altText).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var raster: Image? {
        guard let data else { return nil }
        #if canImport(UIKit)
        guard let decoded = UIImage(data: data) else { return nil }
        return Image(uiImage: decoded)
        #elseif canImport(AppKit)
        guard let decoded = NSImage(data: data) else { return nil }
        return Image(nsImage: decoded)
        #else
        return nil
        #endif
    }
}
