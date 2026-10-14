import SwiftUI
import UniformTypeIdentifiers

struct MacPageWritingView: View {
    @State private var page: WritingPage
    let library: WritingLibrary
    let navigation: EditorNavigationGuard
    @State private var admission = PageBlockWritingAdmission()
    @State private var editToken: UUID?
    @State private var preferences = WritingPreferences.standard
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var activeBlock: NSRange?
    @State private var sourceMode = false
    @State private var preview = false
    @State private var export = false
    @State private var assistant = false
    @State private var action: WritingAIAction?
    @State private var quality = false
    @State private var preferencesSheet = false
    @State private var inspector = false
    @State private var imageImport = false
    @State private var imageAfter: UUID?
    @State private var exportAssets: [String: ExportAsset] = [:]
    @State private var command: MarkdownTextEditor.EditorCommand?
    @State private var jumpTo: Int?
    @Environment(\.scenePhase) private var scenePhase
    init(page: WritingPage, library: WritingLibrary, navigation: EditorNavigationGuard) {
        _page = State(initialValue: page); self.library = library; self.navigation = navigation
    }
    var body: some View {
        let generation = admission.nativeGeneration
        VStack(alignment: .leading, spacing: 0) {
            MacWritingHeader(title: $page.title, words: page.markdown.split(whereSeparator: \.isWhitespace).count, readOnly: library.isReadOnlyRecovery || page.trashed)
            Divider()
            if library.isReadOnlyRecovery || page.trashed {
                ScrollView { Text(page.markdown).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(28) }
            } else if preview { MarkdownPreview(title: page.title, markdown: page.markdown, assets: exportAssets) }
            else if sourceMode {
                MarkdownTextEditor(text: $page.markdown, selection: $selection, preferences: preferences,
                    jumpTo: jumpTo, command: command, onCommandHandled: { command = nil }, onJumpHandled: { jumpTo = nil })
            } else {
                BlockWritingView(markdown: $page.markdown, selection: $selection, initialBlocks: library.blocks(for: page.id), preferences: preferences,
                    onBlocksChanged: { admission.commit(library: library, page: $page, token: $editToken, generation: generation, blocks: $0) },
                    onImage: { after in if finish() { imageAfter = after; imageImport = true } },
                    imageSource: library.store.map { MediaPreviewSource(root: $0.directory, attachments: page.attachments ?? [], refresh: library.mediaPreviewGeneration) },
                    command: command.map { BlockEditorCommand(id: $0.id, prefix: $0.prefix, suffix: $0.suffix) }, onCommandHandled: { command = nil },
                    jumpToUTF16: jumpTo, onJumpHandled: { jumpTo = nil }, canonicalBlocks: { library.blocks(for: page.id) },
                    onReorder: { admission.commit(library: library, page: $page, token: $editToken, generation: generation, blocks: $0, recordSourceHistory: true) },
                    onDraftRejected: { library.preserveRejectedBlocks($0, page: page) })
                    .aiScope(onAI: { value in
                        if finish() { switch value { case .chat: assistant = true; case .proofread: action = .proofread; case .rewrite: action = .rewrite; case .summarize: action = .summarize } }
                    }, activeBlock: { activeBlock = $0 })
            }
        }
        .background { PaperSurface().ignoresSafeArea() }
        .navigationTitle(page.title)
        .toolbar {
            ToolbarItemGroup {
                Button("Fett", systemImage: "bold") { command = .init(prefix: "**", suffix: "**") }.help("Auswahl fett formatieren")
                Button("Kursiv", systemImage: "italic") { command = .init(prefix: "*", suffix: "*") }
                Menu("Schreiben", systemImage: "textformat") {
                    Button("Überschrift") { command = .init(prefix: "## ", suffix: "") }
                    Button("Liste") { command = .init(prefix: "- ", suffix: "") }
                    Button("Link") { command = .init(prefix: "[", suffix: "](https://)") }
                    Button("Bild hinzufügen …") { if finish() { imageAfter = nil; imageImport = true } }
                    Button("Schreibdarstellung …") { if finish() { preferencesSheet = true } }
                }
            }
            ToolbarItem {
                Menu("KI", systemImage: "sparkles") {
                    Button("Chat öffnen") { if finish() { assistant = true } }
                    Button("Lektorat") { if finish() { action = .proofread } }
                    Button("Überarbeiten") { if finish() { action = .rewrite } }
                    Button("Zusammenfassen") { if finish() { action = .summarize } }
                    Button("Textprüfung") { if finish() { quality = true } }
                }
            }
            ToolbarItemGroup {
                Button(sourceMode ? "Schreibansicht" : "Markdown-Quelltext", systemImage: "chevron.left.forwardslash.chevron.right") {
                    if finish() { admission.resetNativeTransaction(); sourceMode.toggle(); preview = false }
                }
                Button(preview ? "Bearbeiten" : "Vorschau", systemImage: "eye") { if prepareExport() { preview.toggle() } }
                Button("Exportieren", systemImage: "square.and.arrow.up") { if prepareExport() { export = true } }
                Button("Seiteninfo und Kommentare", systemImage: "sidebar.right") { if finish() { inspector.toggle() } }
            }
            ToolbarItem {
                Menu("Fassungen", systemImage: "arrow.uturn.backward") {
                    Button("KI-Änderung rückgängig") { if finish(), let saved = admission.undoToolSource(library: library, pageID: page.id) { page = saved } }.disabled(!admission.canUndoToolSource)
                    Button("KI-Änderung wiederholen") { if finish(), let saved = admission.redoToolSource(library: library, pageID: page.id) { page = saved } }.disabled(!admission.canRedoToolSource)
                }
            }
        }
        .inspector(isPresented: $inspector) {
            MacPageInspector(page: $page, library: library, selection: selection, jump: { jumpTo = $0; preview = false }, beforeMutation: finish, restored: { page = $0 }, performMutation: mutate)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 430)
        }
        .sheet(isPresented: $export) { ExportOptionsSheet(page: page, assets: exportAssets, preferenceKey: library.exportPreferenceKey(spaceID: page.spaceID)).frame(width: 720, height: 760) }
        .sheet(isPresented: $assistant) { AssistantPanel(page: page, selection: selection, library: library, activeBlock: activeBlock, apply: apply).frame(width: 740, height: 720) }
        .sheet(item: $action) { item in AssistantPanel(page: page, selection: selection, library: library, initialAction: item, activeBlock: activeBlock, apply: apply).frame(width: 740, height: 720) }
        .sheet(isPresented: $quality) { WritingQualitySheet(page: page, library: library, updated: { page = $0 }, aiAction: { action = $0; quality = false }, performMutation: mutate).frame(width: 680, height: 720) }
        .sheet(isPresented: $preferencesSheet) { WritingPreferencesSheet(initial: preferences) { value in
            do { try library.saveWritingPreferences(value, spaceID: page.spaceID); preferences = value; return nil } catch { return error.localizedDescription }
        }.frame(width: 600, height: 650) }
        .fileImporter(isPresented: $imageImport, allowedContentTypes: [.png, .jpeg, .heic, .gif], allowsMultipleSelection: false) { result in
            do { if let url = try result.get().first { insertImage(url) } } catch { library.saveError = error.localizedDescription }
        }
        .onChange(of: page) { previous, changed in
            if let result = library.processEditorNotification(previous: previous, changed: changed, currentDraft: page, token: editToken) {
                admission.acknowledge(result, library: library); editToken = result.token
                if let revision = result.revision { page.revision = revision }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { _ = finish() } }
        .onAppear { preferences = (try? library.loadWritingPreferences(spaceID: page.spaceID)) ?? .standard; navigation.register(key: page.id.uuidString, action: finish) }
        .onDisappear { library.preserveConflictedDraft(page); _ = finish(); navigation.unregister(key: page.id.uuidString) }
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
private struct MacWritingHeader: View {
    @Binding var title: String
    let words: Int
    let readOnly: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Titel", text: $title, axis: .vertical).lineLimit(1...3).font(.system(.title, design: .serif)).textFieldStyle(.plain).disabled(readOnly)
            Text("\(words) Wörter").font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 28).padding(.vertical, 18)
    }
}
