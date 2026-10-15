import SwiftUI
import UniformTypeIdentifiers

struct MacPageWritingView: View {
    @State private var page: WritingPage
    let library: WritingLibrary
    let navigation: EditorNavigationGuard
    @Binding var inspector: Bool
    let headingJump: WritingHeadingJump?
    let navigate: (PageLinkTarget) -> Bool
    @State private var admission = PageBlockWritingAdmission()
    @State private var editToken: UUID?
    @State private var preferences = MacWritingAppearance.defaults
    @State private var menuContext = MacEditorCommandContext()
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var activeBlock: NSRange?
    @State private var sourceMode = false
    @State private var preview = false
    @State private var export = false
    @State private var assistant = false
    @State private var action: WritingAIAction?
    @State private var quality = false
    @State private var preferencesSheet = false
    @State private var imageImport = false
    @State private var imageAfter: UUID?
    @State private var referencePicker = false
    @State private var pageLinks = false
    @State private var attachments = false
    @State private var tableSession: PageTableSession?
    @State private var exportAssets: [String: ExportAsset] = [:]
    @State private var command: MarkdownTextEditor.EditorCommand?
    @State private var jumpTo: Int?
    @Environment(\.scenePhase) private var scenePhase
    init(page: WritingPage, library: WritingLibrary, navigation: EditorNavigationGuard, inspector: Binding<Bool>,
         headingJump: WritingHeadingJump?, navigate: @escaping (PageLinkTarget) -> Bool) {
        _page = State(initialValue: page); self.library = library; self.navigation = navigation
        _inspector = inspector
        self.headingJump = headingJump; self.navigate = navigate
    }
    var body: some View {
        let generation = admission.nativeGeneration
        MacManuscriptSurface {
            VStack(alignment: .leading, spacing: 0) {
                if library.isReadOnlyRecovery || page.trashed {
                    ScrollView { Text(page.markdown).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(28) }
                } else if preview { MarkdownPreview(title: page.title, markdown: page.markdown, assets: exportAssets) }
                else if sourceMode {
                    MarkdownTextEditor(text: $page.markdown, selection: $selection, preferences: preferences,
                        jumpTo: jumpTo, command: command, onCommandHandled: { command = nil }, onJumpHandled: { jumpTo = nil })
                } else {
                    BlockWritingView(markdown: $page.markdown, selection: $selection, initialBlocks: library.blocks(for: page.id), preferences: preferences,
                        onBlocksChanged: { admission.commit(library: library, page: $page, token: $editToken, generation: generation, blocks: $0) },
                        onPageReference: { if finish() { referencePicker = true }; return nil },
                        onImage: { after in if finish() { imageAfter = after; imageImport = true } },
                        onTable: openTable,
                        imageSource: library.store.map { MediaPreviewSource(root: $0.directory, attachments: page.attachments ?? [], refresh: library.mediaPreviewGeneration) },
                        command: command.map { BlockEditorCommand(id: $0.id, prefix: $0.prefix, suffix: $0.suffix) }, onCommandHandled: { command = nil },
                        jumpToUTF16: jumpTo, onJumpHandled: { jumpTo = nil }, canonicalBlocks: { library.blocks(for: page.id) },
                        onReorder: { admission.commit(library: library, page: $page, token: $editToken, generation: generation, blocks: $0, recordSourceHistory: true) },
                        onDraftRejected: { library.preserveRejectedBlocks($0, page: page) })
                        .aiScope(onAI: { value in
                            if finish() { switch value { case .chat: assistant = true; case .proofread: action = .proofread; case .rewrite: action = .rewrite; case .summarize: action = .summarize } }
                        }, activeBlock: { activeBlock = $0 })
                        .padding(.horizontal, 12).padding(.top, 24)
                }
                MacWritingStatus(words: page.markdown.split(whereSeparator: \.isWhitespace).count, characters: page.markdown.count,
                    mode: preview ? .preview : sourceMode ? .source : .writing)
            }
        }
        .navigationTitle(page.title)
        .focusedSceneValue(\.macEditor, menuContext)
        .toolbar {
            ToolbarItemGroup {
                Picker("Ansicht", selection: Binding(get: { preview ? 2 : (sourceMode ? 1 : 0) }, set: { value in
                    handle(value == 2 ? .preview : value == 1 ? .source : .writing)
                })) {
                    Label("Schreiben", systemImage: "pencil").tag(0)
                    Label("Markdown", systemImage: "chevron.left.forwardslash.chevron.right").tag(1)
                    Label("Vorschau", systemImage: "eye").tag(2)
                }.pickerStyle(.segmented).labelStyle(.iconOnly).controlSize(.small).help("Schreiben, Markdown-Quelltext oder Vorschau")
            }
            ToolbarItemGroup {
                Menu("Format", systemImage: "textformat") {
                    Button("Fett") { handle(.bold) }.disabled(!menuContext.editable)
                    Button("Kursiv") { handle(.italic) }.disabled(!menuContext.editable)
                    Button("Überschrift") { handle(.heading) }.disabled(!menuContext.editable)
                    Button("Liste") { handle(.list) }.disabled(!menuContext.editable)
                    Button("Link") { handle(.link) }.disabled(!menuContext.editable)
                    Button("Seitenverweis einfügen …") { handle(.reference) }.disabled(!menuContext.editable)
                    Button("Bild hinzufügen …") { handle(.image) }.disabled(!menuContext.editable)
                    Divider()
                    Button("Schreibdarstellung …") { handle(.appearance) }
                    Button("Textänderung rückgängig") { handle(.undoAI) }.disabled(!admission.canUndoToolSource)
                    Button("Textänderung wiederholen") { handle(.redoAI) }.disabled(!admission.canRedoToolSource)
                }
                Button("Lektorat", systemImage: "text.badge.checkmark") { handle(.proofread) }
                    .labelStyle(.titleAndIcon).disabled(!menuContext.editable).help("Lektorat für die aktuelle Seite öffnen")
                Menu("KI-Assistent", systemImage: "sparkles") {
                    Button("Chat öffnen …") { handle(.assistant) }
                    Button("Lektorat …") { handle(.proofread) }.disabled(!menuContext.editable)
                    Button("Überarbeiten …") { handle(.rewrite) }.disabled(!menuContext.editable)
                    Button("Zusammenfassen …") { handle(.summarize) }
                    Button("Textprüfung …") { handle(.quality) }
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Exportieren", systemImage: "square.and.arrow.up") { handle(.export) }.help("Exportieren (⇧⌘E)")
                Button("Seiteninfo und Kommentare", systemImage: "sidebar.right") { handle(.inspector) }
            }
        }
        .inspector(isPresented: $inspector) {
            MacPageInspector(page: $page, library: library, selection: selection, jump: { jumpTo = $0; preview = false }, beforeMutation: finish, restored: { page = $0 }, performMutation: mutate)
                .inspectorColumnWidth(min: 260, ideal: 290, max: 360)
        }
        .sheet(isPresented: $export) { ExportOptionsSheet(page: page, assets: exportAssets, preferenceKey: library.exportPreferenceKey(spaceID: page.spaceID)).frame(width: 720, height: 760) }
        .sheet(isPresented: $assistant) { AssistantPanel(page: page, selection: selection, library: library, activeBlock: activeBlock, apply: apply).frame(width: 740, height: 720) }
        .sheet(item: $action) { item in AssistantPanel(page: page, selection: selection, library: library, initialAction: item, activeBlock: activeBlock, apply: apply).frame(width: 740, height: 720) }
        .sheet(isPresented: $quality) { WritingQualitySheet(page: page, library: library, updated: { page = $0 }, aiAction: { action = $0; quality = false }, performMutation: mutate).frame(width: 680, height: 720) }
        .sheet(isPresented: $preferencesSheet) { WritingPreferencesSheet(initial: preferences) { value in
            do { try library.saveWritingPreferences(value, spaceID: page.spaceID); preferences = value; return nil } catch { return error.localizedDescription }
        }.frame(width: 600, height: 650) }
        .sheet(isPresented: $referencePicker) { PageReferenceSheet(pageID: page.id, library: library, insert: insertReference).frame(width: 620, height: 600) }
        .sheet(isPresented: $pageLinks) { PageLinksSheet(pageID: page.id, library: library, navigate: navigate).frame(width: 620, height: 600) }
        .sheet(isPresented: $attachments) { AttachmentDashboardSheet(library: library, pageID: page.id, navigate: { navigate(PageLinkTarget(pageID: $0)) }).frame(width: 680, height: 640) }
        .sheet(item: $tableSession) { item in
            TableEditingSheet(source: item.source, apply: { replacement in
                guard item.pageID == page.id, (try? MarkdownTable(replacement)) != nil else { return "Die Tabelle ist kein gültiges rechteckiges Markdown." }
                guard let saved = mutate({ library.replaceBlock(pageID: item.pageID, baseRevision: item.revision,
                    blockID: item.blockID, expectedSource: item.source, replacement: replacement) }) else {
                    return library.saveError ?? "Die Tabelle konnte nicht gespeichert werden."
                }
                item.revision = saved.revision; item.source = replacement; page = saved
                return nil
            }).frame(width: 740, height: 680)
        }
        .fileImporter(isPresented: $imageImport, allowedContentTypes: [.png, .jpeg, .heic, .gif], allowsMultipleSelection: false) { result in
            do { if let url = try result.get().first { insertImage(url) } } catch { library.saveError = error.localizedDescription }
        }
        .onChange(of: page) { previous, changed in
            if let result = library.processEditorNotification(previous: previous, changed: changed, currentDraft: page, token: editToken) {
                admission.acknowledge(result, library: library); editToken = result.token
                if let revision = result.revision { page.revision = revision }
            }
        }
        .onChange(of: admission.canUndoToolSource) { _, _ in refreshMenuContext() }
        .onChange(of: admission.canRedoToolSource) { _, _ in refreshMenuContext() }
        .onChange(of: headingJump?.id) { _, _ in applyHeadingJump() }
        .onChange(of: library.isReadOnlyRecovery || page.trashed) { _, _ in refreshMenuContext() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { _ = finish() } }
        .onAppear { preferences = (try? library.loadWritingPreferences(spaceID: page.spaceID, defaultValue: MacWritingAppearance.defaults)) ?? MacWritingAppearance.defaults; menuContext.perform = handle; refreshMenuContext(); navigation.register(key: page.id.uuidString, action: finish); applyHeadingJump() }
        .onDisappear { library.preserveConflictedDraft(page); _ = finish(); navigation.unregister(key: page.id.uuidString); menuContext.perform = nil }
    }
    private func refreshMenuContext() {
        menuContext.editable = !library.isReadOnlyRecovery && !page.trashed
        menuContext.canUndoAI = admission.canUndoToolSource && menuContext.editable
        menuContext.canRedoAI = admission.canRedoToolSource && menuContext.editable
    }
    private func handle(_ intent: MacEditorIntent) {
        switch intent {
        case .bold: if menuContext.editable { command = .init(prefix: "**", suffix: "**") }
        case .italic: if menuContext.editable { command = .init(prefix: "*", suffix: "*") }
        case .heading: if menuContext.editable { command = .init(prefix: "## ", suffix: "") }
        case .list: if menuContext.editable { command = .init(prefix: "- ", suffix: "") }
        case .link: if menuContext.editable { command = .init(prefix: "[", suffix: "](https://)") }
        case .reference: if menuContext.editable, finish() { referencePicker = true }
        case .links: if finish() { pageLinks = true }
        case .attachments: if finish() { attachments = true }
        case .image: if menuContext.editable, finish() { imageAfter = nil; imageImport = true }
        case .appearance: if finish() { preferencesSheet = true }
        case .assistant: if finish() { assistant = true }
        case .proofread: if menuContext.editable, finish() { action = .proofread }
        case .rewrite: if menuContext.editable, finish() { action = .rewrite }
        case .summarize: if finish() { action = .summarize }
        case .quality: if finish() { quality = true }
        case .export: if prepareExport() { export = true }
        case .inspector:
            if finish() { inspector.toggle() }
        case .preview: if prepareExport() { preview = true }
        case .writing, .source:
            if finish() {
                let nextSource = intent == .source
                if sourceMode != nextSource { admission.resetNativeTransaction() }
                sourceMode = nextSource; preview = false
            }
        case .undoAI:
            if menuContext.editable, finish(), let saved = admission.undoToolSource(library: library, pageID: page.id) { page = saved }
        case .redoAI:
            if menuContext.editable, finish(), let saved = admission.redoToolSource(library: library, pageID: page.id) { page = saved }
        }
    }
    private func finish() -> Bool {
        if !sourceMode, admission.hasAcceptedWrite {
            guard admission.finish(library: library) else { return false }
            admission.refreshOwnedText(library: library, page: $page)
        } else { guard library.finishTyping(editToken) else { return false } }
        editToken = nil; return true
    }
    private func mutate(_ operation: @MainActor () -> WritingPage?) -> WritingPage? {
        guard finish() else { return nil }
        return admission.performToolMutation(library: library, pageID: page.id, operation: operation)
    }
    private func apply(_ target: AssistantTextTarget, _ response: String) -> Bool {
        guard target.pageID == page.id, let saved = mutate({ library.applyAssistantText(target, response: response) }) else { return false }
        page = saved; return true
    }
    private func prepareExport() -> Bool {
        guard finish() else { return false }
        do { exportAssets = try library.exportAssets(for: page); return true } catch { library.saveError = error.localizedDescription; return false }
    }
    private func openTable(_ blockID: UUID) {
        guard menuContext.editable, finish(), let current = library.currentPage(page.id),
              let block = library.blocks(for: page.id).first(where: { $0.id == blockID }),
              (try? MarkdownTable(block.markdown)) != nil else {
            if library.saveError == nil { library.saveError = "Diese Tabelle kann im Markdown-Quelltext bearbeitet werden." }
            return
        }
        tableSession = PageTableSession(pageID: current.id, blockID: block.id, revision: current.revision, source: block.markdown)
    }
    private func insertReference(_ title: String, _ target: PageLinkTarget) -> Bool {
        guard finish(), library.resolvePageTarget(target) != nil,
              var current = library.currentPage(page.id), current.revision == page.revision else {
            if library.saveError == nil { library.saveError = "Die Seite wurde inzwischen geändert. Bitte erneut öffnen." }
            return false
        }
        let label = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        current.markdown += "\n\n[" + label + "](" + target.url.absoluteString + ")\n"
        guard let saved = mutate({
            guard library.update(current) != nil else { return nil }
            return library.currentPage(current.id)
        }) else { return false }
        page = saved; return true
    }
    private func applyHeadingJump() {
        guard let headingJump, headingJump.pageID == page.id else { return }
        guard headingJump.revision == page.revision else { library.saveError = "Die Seite wurde seit dem Sprungziel geändert."; return }
        preview = false; jumpTo = headingJump.offset
    }
    private func insertImage(_ url: URL) {
        guard finish(), let store = library.store else { return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 64 * 1024 * 1024 else { throw ExportError.invalidMetadata("Das Bild ist zu groß oder leer.") }
            let data = try Data(contentsOf: url)
            let mediaType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            if let saved = mutate({
                do {
                    _ = try store.addImageBlock(pageID: page.id, data: data, mediaType: mediaType, filename: url.lastPathComponent,
                        altText: url.deletingPathExtension().lastPathComponent, afterBlockID: imageAfter, baseRevision: page.revision)
                    library.reload(); return library.currentPage(page.id)
                } catch { library.saveError = error.localizedDescription; return nil }
            }) { page = saved }
        } catch { library.saveError = error.localizedDescription }
    }
}
private struct MacWritingStatus: View {
    let words: Int
    let characters: Int
    let mode: MacEditorIntent
    var body: some View {
        HStack(spacing: 14) {
            if words == 1 { Text("1 Wort") }
            else { Text("\(words, format: .number) Wörter") }
            if characters == 1 { Text("1 Zeichen") }
            else { Text("\(characters, format: .number) Zeichen") }
            Spacer(minLength: 8)
            Text(mode == .preview ? "Vorschau" : mode == .source ? "Markdown" : "Schreibansicht")
        }
        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        .padding(.horizontal, 24).padding(.vertical, 10)
        .overlay(alignment: .top) { Divider().opacity(0.5).padding(.horizontal, 24) }
    }
}
