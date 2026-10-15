import SwiftUI
import UIKit

private struct PageExportPresentation: Identifiable {
    let id = UUID()
    let page: WritingPage
    let assets: [String: ExportAsset]
    let preferenceKey: String?
}

struct PageWritingView: View {
    @State private var inspectorSection = 0
    @State var page: WritingPage
    let library: WritingLibrary
    @Binding var focus: Bool
    let createSubpage: () -> Void
    var closeLibrary: (() -> Void)? = nil
    var navigationGuard: EditorNavigationGuard? = nil
    var navigate: ((PageLinkTarget) -> Bool)? = nil
    var headingJump: WritingHeadingJump? = nil
    var canGoBack = false
    var canGoForward = false
    var goBack: (() -> Void)? = nil
    var goForward: (() -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var editToken: UUID?
    @State private var blockWriteAdmission = PageBlockWritingAdmission()
    @State private var inspector = false
    @State private var sharedMarkdown: SharedMarkdown?
    @State private var assistant = false
    @State private var preview = false
    @State private var sourceMode = false
    @State private var tools = false
    @State private var ownerShare: OwnerSharePresentation?
    @State private var showingTasks = false
    @State private var showingICloud = false
    @State private var pageLinks = false
    @State private var referencePicker = false
    @State private var insertingImage = false
    @State private var imageAfterBlock: UUID?
    @State private var tableSession: PageTableSession?
    @State private var attachmentDashboard = false
    @State private var writingPreferences = WritingPreferences.standard
    @State private var editorSettings = false
    @State private var exportAssets: [String: ExportAsset] = [:]
    @State private var exportPresentation: PageExportPresentation?
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var jumpTo: Int?
    @State private var command: MarkdownTextEditor.EditorCommand?
    @State private var keyboardRequestID: UUID?
    @State private var commandUnavailable = false
    @State private var reviewingQuality = false
    @State private var pendingAIAction: WritingAIAction?
    @State private var writingAction: WritingAIAction?
    @State private var assistantPrompt = ""
    @State private var assistantRevisionMode = false
    @State private var keyboard = KeyboardState()
    @State private var activeBlockRange: NSRange?
    @State private var heldSelection: (range: NSRange, revision: UUID)?
    @State private var writingScope = EditorTextScope.page
    /// Phone landscape: title, status and writing actions yield their height to the editor.
    private var compactHeight: Bool { verticalSizeClass == .compact }
    private var showsWritingActions: Bool { !focus && !page.trashed && !library.isReadOnlyRecovery }
    /// The inline action bar yields to the keyboard and to landscape height; the menu section takes over.
    private var writingBarHidden: Bool { compactHeight || keyboard.isVisible }
    private var compactChrome: Bool { focus || compactHeight || keyboard.isVisible }
    @ViewBuilder private var writingActionButtons: some View {
        Button("Lektorat") { openWritingAction(.proofread) }
        Button("Überarbeiten") { openWritingAction(.rewrite) }
        Button("Zusammenfassen") { openWritingAction(.summarize) }
    }
    private func finishTyping() -> Bool {
        if !$sourceMode.wrappedValue, blockWriteAdmission.hasAcceptedWrite {
            guard blockWriteAdmission.finish(library: library) else { return false }
            blockWriteAdmission.refreshOwnedText(library: library, page: $page)
            $editToken.wrappedValue = nil
            return true
        }
        return library.finishTyping($editToken.wrappedValue)
    }
    /// Receiving API for the editor: the block that holds the caret, in UTF-16 offsets of `page.markdown`.
    func reportActiveBlock(_ range: NSRange?) { activeBlockRange = range }
    /// Accessory "KI" button; acts on selection, else active block, else page.
    func openAI(_ action: WritingAIAction = .rewrite) { openWritingAction(action) }
    private func captureScope() -> EditorTextScope {
        let held = heldSelection.flatMap { $0.revision == page.revision ? $0.range : nil }
        return .resolve(selection: selection.length > 0 ? selection : held, activeBlock: activeBlockRange, utf16Length: page.markdown.utf16.count)
    }
    private func openWritingAction(_ action: WritingAIAction) {
        let scope = captureScope()
        guard prepareNavigation() else { return }
        editToken = nil; writingScope = scope; writingAction = action
    }
    private func performToolMutation(_ operation: @MainActor () -> WritingPage?) -> WritingPage? {
        blockWriteAdmission.performToolMutation(library: library, pageID: page.id, operation: operation)
    }
    var body: some View {
        let nativeGeneration = blockWriteAdmission.nativeGeneration
        VStack(spacing: 0) {
            if library.isReadOnlyRecovery {
                Text(page.title).font(.title).frame(maxWidth: .infinity, alignment: .leading).padding()
                Label("Nur Lesen · Wiederherstellung erforderlich", systemImage: "lock.doc")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            } else { PageTitleHeader(title: $page.title, favorite: page.favorite, focus: compactChrome) }
            Divider()
            if library.isReadOnlyRecovery {
                ScrollView { Text(page.markdown).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding() }
            } else if preview {
                MarkdownPreview(title: page.title, markdown: page.markdown, assets: exportAssets)
            } else if !sourceMode {
                BlockWritingView(markdown: $page.markdown, selection: $selection, initialBlocks: library.blocks(for: page.id), preferences: writingPreferences, onBlocksChanged: { blocks in
                    blockWriteAdmission.commit(library: library, page: $page, token: $editToken, generation: nativeGeneration, blocks: blocks)
                }, onPageReference: { if prepareNavigation() { referencePicker = true }; return nil }, onPrompt: { if prepareNavigation() { editToken = nil; assistant = true } }, onImage: { after in
                    if finishTyping() { editToken = nil; imageAfterBlock = after; insertingImage = true }
                }, onTable: openTable, imageSource: library.store.map {
                    MediaPreviewSource(root: $0.directory, attachments: page.attachments ?? [], refresh: library.mediaPreviewGeneration)
                }, command: command.map { BlockEditorCommand(id: $0.id, prefix: $0.prefix, suffix: $0.suffix) }, onCommandHandled: { command = nil }, jumpToUTF16: jumpTo, onJumpHandled: { jumpTo = nil }, onCommandUnavailable: { commandUnavailable = true }, canonicalBlocks: { library.blocks(for: page.id) }, keyboardRequestID: keyboardRequestID, onKeyboardRequestHandled: { keyboardRequestID = nil }, onReorder: { blocks in
                    blockWriteAdmission.commit(library: library, page: $page, token: $editToken, generation: nativeGeneration, blocks: blocks, recordSourceHistory: true)
                }, onDraftRejected: { blocks in
                    library.preserveRejectedBlocks(blocks, page: page)
                }).aiScope(onAI: { action in
                    switch action {
                    case .proofread: openAI(.proofread)
                    case .rewrite: openAI(.rewrite)
                    case .summarize: openAI(.summarize)
                    case .chat: if prepareNavigation() { editToken = nil; assistant = true }
                    }
                }, activeBlock: { reportActiveBlock($0) })
            } else {
                MarkdownTextEditor(text: $page.markdown, selection: $selection, preferences: writingPreferences, jumpTo: jumpTo, command: command, onCommandHandled: { command = nil }, onJumpHandled: { jumpTo = nil }, onCommandUnavailable: { commandUnavailable = true }, keyboardRequestID: keyboardRequestID, onKeyboardRequestHandled: { keyboardRequestID = nil })
                    .frame(maxWidth: writingPreferences.contentWidth ?? .infinity)
                    .frame(maxWidth: .infinity)
            }
            if sourceMode && !preview && !library.isReadOnlyRecovery && !keyboard.isVisible { WritingFormattingToolbar(commands: writingPreferences.visibleCommands) { value in command = .init(prefix: value.prefix, suffix: value.suffix) } }
            if !writingBarHidden { WritingStatusBar(markdown: page.markdown, saved: library.lastSaved, goal: page.wordGoal) }
        }
        .background { PaperSurface().ignoresSafeArea() }
        .alert("Formatierung hier nicht verfügbar", isPresented: $commandUnavailable) {
            Button("OK", role: .cancel) {}
        } message: { Text("Aktivieren Sie einen Textblock, der diesen Befehl unterstützt. Beenden Sie zunächst eine laufende Texteingabe.") }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Zurück", systemImage: "chevron.backward") { goBack?() }.disabled(!canGoBack).keyboardShortcut("[", modifiers: .command)
                Button("Vorwärts", systemImage: "chevron.forward") { goForward?() }.disabled(!canGoForward).keyboardShortcut("]", modifiers: .command)
            }.visibilityPriority(.low)
            ToolbarItem(placement: .primaryAction) {
                Menu("KI", systemImage: "sparkles") {
                    writingActionButtons
                    Button("Chat öffnen") { if prepareNavigation() { editToken = nil; assistantPrompt = ""; assistantRevisionMode = false; assistant = true } }
                }.disabled(library.isReadOnlyRecovery)
            }
            ToolbarItem(placement: .topBarPinnedTrailing) {
                Menu("Mehr", systemImage: "ellipsis.circle") {
                    Button("Tastatur einblenden", systemImage: "keyboard") {
                        preview = false; keyboardRequestID = UUID()
                    }.disabled(page.trashed || library.isReadOnlyRecovery)
                        .accessibilityIdentifier("showWritingKeyboard")
                    if writingBarHidden && showsWritingActions {
                        Section("Schreibaktionen") { writingActionButtons }
                    }
                    Button("Textänderung rückgängig", systemImage: "arrow.uturn.backward") { undoToolSource() }
                        .disabled(!blockWriteAdmission.canUndoToolSource || library.isReadOnlyRecovery)
                    Button("Textänderung wiederholen", systemImage: "arrow.uturn.forward") { redoToolSource() }
                        .disabled(!blockWriteAdmission.canRedoToolSource || library.isReadOnlyRecovery)
                    if blockWriteAdmission.isToolHistoryLimited {
                        Text("Ältere Änderungen finden Sie im Versionsverlauf.")
                    }
                    Button(preview ? "Quelltext" : "Vorschau", systemImage: preview ? "chevron.left.forwardslash.chevron.right" : "eye") { if finishTyping() { editToken = nil; do { exportAssets = try library.exportAssets(for: page); preview.toggle() } catch { library.saveError = error.localizedDescription } } }
                        .keyboardShortcut("p", modifiers: [.command, .shift])
                    Button(focus ? "Fokus beenden" : "Fokus", systemImage: focus ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") { focus.toggle() }
                        .keyboardShortcut("f", modifiers: [.command, .shift])
                    Button(sourceMode ? "Schreibansicht" : "Markdown-Quelltext", systemImage: "text.alignleft") { if finishTyping() { editToken = nil; blockWriteAdmission.resetNativeTransaction(); sourceMode.toggle(); preview = false } }
                    Button(page.favorite ? "Favorit entfernen" : "Als Favorit markieren", systemImage: "star") { page.favorite.toggle() }.disabled(library.isReadOnlyRecovery)
                    Button("Exportieren", systemImage: "square.and.arrow.up") { if finishTyping() { editToken = nil; do { exportPresentation = PageExportPresentation(page: page, assets: try library.exportAssets(for: page), preferenceKey: library.exportPreferenceKey(spaceID: page.spaceID)) } catch { library.saveError = error.localizedDescription } } }
                    Button("iCloud-Synchronisation", systemImage: "icloud") {
                        if prepareNavigation() { showingICloud = true }
                    }.accessibilityIdentifier("pageICloud")
                    if library.saveError != nil || library.isReadOnlyRecovery {
                        Button("Entwurf als Markdown sichern", systemImage: "doc.badge.arrow.up") {
                            sharedMarkdown = library.exportMarkdown(page)
                        }
                    }
                    Menu("Dokument-Werkzeuge", systemImage: "wrench.and.screwdriver") {
                        Button("Textprüfung und Lektorat", systemImage: "text.badge.checkmark") { if finishTyping() { editToken = nil; reviewingQuality = true } }.disabled(library.isReadOnlyRecovery)
                        Button("Seitenregeln, Prompts und Bilder", systemImage: "slider.horizontal.3") { if finishTyping() { editToken = nil; tools = true } }.disabled(library.isReadOnlyRecovery)
                        Button("Verweise und Rückverweise", systemImage: "link") { if finishTyping() { editToken = nil; pageLinks = true } }
                        Button("Anhänge und Verwendung", systemImage: "paperclip") { if prepareNavigation() { attachmentDashboard = true } }
                        Button("Editor-Einstellungen", systemImage: "textformat") { if prepareNavigation() { loadWritingPreferences(); editorSettings = true } }
                        Button("Geplante Aufgaben", systemImage: "calendar.badge.clock") { if prepareNavigation() { showingTasks = true } }
                        Button("Über iCloud teilen", systemImage: "person.2") { if prepareNavigation() { ownerShare = OwnerSharePresentation(scope: .page(page.id)) } }.disabled(page.trashed || library.isReadOnlyRecovery)
                        Menu("Seitenart", systemImage: "doc.text") {
                            Button("Manuskripttext") { changePurpose(.writing) }
                            Button("Recherchematerial") { changePurpose(.material) }
                            Button("Vorlage") { changePurpose(.template) }
                        }.disabled(page.trashed || library.isReadOnlyRecovery)
                        Button("Unterseite erstellen", systemImage: "doc.badge.plus", action: createSubpage).disabled(library.isReadOnlyRecovery)
                        Button("Duplizieren", systemImage: "doc.on.doc") {
                            if finishTyping() { editToken = nil; library.duplicatePage(page) }
                        }.disabled(library.isReadOnlyRecovery)
                        if let closeLibrary { Button("Zum Dateibrowser", systemImage: "folder", action: closeLibrary) }
                    }
                    Button(page.trashed ? "Wiederherstellen" : "In den Papierkorb", systemImage: "trash") { page.trashed.toggle() }.disabled(library.isReadOnlyRecovery)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Gliederung und Statistik", systemImage: "sidebar.right") { if finishTyping() { editToken = nil; inspector.toggle() } }
            }.visibilityPriority(.low)
        }
        .safeAreaBar(edge: .bottom) {
            if showsWritingActions && !writingBarHidden {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { writingActionButtons }.fixedSize(horizontal: true, vertical: false)
                    Menu("Schreibaktionen", systemImage: "sparkles") { writingActionButtons }
                }.font(.footnote).buttonStyle(.borderless).frame(maxWidth: .infinity).padding(.vertical, 6).background(.bar)
            }
        }
        .inspector(isPresented: $inspector) {
            VStack(alignment: .leading, spacing: 0) {
                Picker("Seitenbereich", selection: $inspectorSection) {
                    Text("Seiteninfo").tag(0)
                    Text("Kommentare & Verlauf").tag(1)
                }.pickerStyle(.segmented).labelsHidden().fixedSize(horizontal: false, vertical: true).padding()
                if inspectorSection == 0 {
                    PageInspector(markdown: page.markdown, goal: $page.wordGoal, tags: $page.tags, jump: {
                        jumpTo = $0; preview = false
                        if horizontalSizeClass == .compact { inspector = false }
                    }).disabled(library.isReadOnlyRecovery)
                } else {
                    PageReviewPanel(page: page, selection: selection, library: library, restored: { page = $0 }, beforeMutation: {
                        guard finishTyping() else { return false }
                        editToken = nil; return true
                    }, performMutation: performToolMutation).disabled(library.isReadOnlyRecovery)
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background { PaperSurface().ignoresSafeArea() }
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .sheet(item: $exportPresentation) { item in ExportOptionsSheet(page: item.page, assets: item.assets, preferenceKey: item.preferenceKey) }
        .sheet(item: $sharedMarkdown) { item in MarkdownShareSheet(url: item.url) }
        .sheet(isPresented: $tools) { PageToolsSheet(page: page, library: library, updated: { page = $0 }, performMutation: performToolMutation, closed: { tools = false }) }
        .sheet(item: $ownerShare) { ICloudOwnerShareSheet(presentation: $0, library: library) }
        .sheet(isPresented: $showingTasks) { LocalTasksSheet(library: library, pageID: page.id) }
        .sheet(isPresented: $showingICloud) { ICloudSettingsView(library: library) }
        .sheet(isPresented: $editorSettings) {
            WritingPreferencesSheet(initial: writingPreferences) { value in
                do { try library.saveWritingPreferences(value, spaceID: page.spaceID); writingPreferences = value; return nil }
                catch { return "Die Einstellungen konnten nicht gespeichert werden: \(error.localizedDescription)" }
            }
        }
        .task(id: library.libraryIdentity.uuidString + ":" + page.spaceID.uuidString) { loadWritingPreferences() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in loadWritingPreferences() }
        .sheet(isPresented: $attachmentDashboard) {
            AttachmentDashboardSheet(library: library, pageID: page.id, navigate: { id in navigate?(PageLinkTarget(pageID: id)) ?? false })
        }
        .sheet(isPresented: $reviewingQuality, onDismiss: {
            if let pendingAIAction { writingAction = pendingAIAction; self.pendingAIAction = nil }
        }) {
            WritingQualitySheet(page: page, library: library, updated: { page = $0 }, aiAction: { action in pendingAIAction = action; reviewingQuality = false }, performMutation: performToolMutation)
        }
        .sheet(isPresented: $insertingImage) { ImageBlockPicker(page: page, library: library, afterBlockID: imageAfterBlock, updated: { page = $0 }, performMutation: performToolMutation) }
        .sheet(item: $tableSession) { item in
            TableEditingSheet(source: item.source, apply: { replacement in
                guard (try? MarkdownTable(replacement)) != nil else { return "Die Tabelle ist kein gültiges rechteckiges Markdown." }
                guard let saved = performToolMutation({ library.replaceBlock(pageID: item.pageID, baseRevision: item.revision, blockID: item.blockID, expectedSource: item.source, replacement: replacement) }) else {
                    return library.saveError ?? "Die Tabelle konnte nicht gespeichert werden."
                }
                item.revision = saved.revision; item.source = replacement; page = saved
                return nil
            })
        }
        .sheet(isPresented: $referencePicker) {
            PageReferenceSheet(pageID: page.id, library: library, insert: insertReference)
        }
        .sheet(isPresented: $pageLinks) { PageLinksSheet(pageID: page.id, library: library, navigate: { navigate?($0) ?? false }) }
        .sheet(item: $writingAction) { action in
            AssistantPanel(page: page, selection: writingScope.kind == .selection ? writingScope.range : NSRange(location: 0, length: 0), library: library, initialAction: action, activeBlock: writingScope.kind == .block ? writingScope.range : nil, apply: applyAssistantProposal)
        }
        .sheet(isPresented: $assistant) {
            AssistantPanel(page: page, selection: selection, library: library, initialPrompt: assistantPrompt, initialRevisionMode: assistantRevisionMode, activeBlock: activeBlockRange, apply: applyAssistantProposal)
        }
        .environment(keyboard)
        .background { KeyboardWindowReader(state: keyboard).frame(width: 0, height: 0) }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { keyboard.handle($0) }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboard.hide() }
        .onChange(of: selection) { _, value in
            if value.length > 0 { heldSelection = (value, page.revision) }
            else if keyboard.isVisible { heldSelection = nil }
        }
        .onChange(of: page) { previous, changed in
            if let result = library.processEditorNotification(previous: previous, changed: changed, currentDraft: page, token: editToken) {
                blockWriteAdmission.acknowledge(result, library: library)
                editToken = result.token
                if let revision = result.revision { page.revision = revision }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, finishTyping() { editToken = nil }
        }
        .onAppear {
            navigationGuard?.register(key: navigationKey) {
                prepareNavigation()
            }
            applyHeadingJump()
        }
        .onChange(of: headingJump?.id) { _, _ in applyHeadingJump() }
        .onDisappear {
            navigationGuard?.unregister(key: navigationKey)
            library.preserveConflictedDraft(page)
            if finishTyping() { editToken = nil }
        }
    }
    private func applyAssistantProposal(_ target: AssistantTextTarget, _ response: String) -> Bool {
        guard target.pageID == page.id,
              let saved = performToolMutation({ library.applyAssistantText(target, response: response) }) else { return false }
        editToken = nil; page = saved; return true
    }
    private func undoToolSource() {
        guard finishTyping() else { return }
        editToken = nil
        if let saved = blockWriteAdmission.undoToolSource(library: library, pageID: page.id) { page = saved }
    }
    private func redoToolSource() {
        guard finishTyping() else { return }
        editToken = nil
        if let saved = blockWriteAdmission.redoToolSource(library: library, pageID: page.id) { page = saved }
    }
    private var navigationKey: String { library.libraryIdentity.uuidString + ":" + page.id.uuidString }
    private func loadWritingPreferences() {
        do {
            let value = try library.loadWritingPreferences(spaceID: page.spaceID)
            if value != writingPreferences { writingPreferences = value }
        } catch {
            library.saveError = "Gespeicherte Editor-Einstellungen sind nicht verfügbar. Standardwerte werden angezeigt; die gespeicherten Daten bleiben erhalten."
            writingPreferences = .standard
        }
    }
    private func openTable(_ blockID: UUID) {
        guard prepareNavigation(), let current = library.currentPage(page.id),
              let block = library.blocks(for: page.id).first(where: { $0.id == blockID }),
              (try? MarkdownTable(block.markdown)) != nil else {
            if library.saveError == nil { library.saveError = "Diese Tabelle kann im Markdown-Quelltext bearbeitet werden." }
            return
        }
        tableSession = PageTableSession(pageID: current.id, blockID: block.id, revision: current.revision, source: block.markdown)
    }
    private func prepareNavigation() -> Bool {
        guard finishTyping() else { return false }
        editToken = nil
        guard library.persistBeforeNavigation(page, token: nil) else { return false }
        if let latest = library.currentPage(page.id) { page = latest }
        return true
    }
    private func changePurpose(_ purpose: PagePurpose) {
        guard finishTyping() else { return }
        editToken = nil
        if let saved = performToolMutation({ library.changePurpose(page, purpose: purpose) }) { page = saved }
    }
    private func insertReference(_ title: String, _ target: PageLinkTarget) -> Bool {
        guard library.resolvePageTarget(target) != nil,
              var current = library.currentPage(page.id), current.revision == page.revision else { library.saveError = "Die Seite wurde inzwischen geändert. Bitte erneut öffnen."; return false }
        let safe = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]").replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        current.markdown += "\n\n[" + safe + "](" + target.url.absoluteString + ")\n"
        guard let saved = performToolMutation({
            guard let revision = library.update(current) else { return nil }
            current.revision = revision; return library.currentPage(current.id)
        }) else { return false }
        page = saved; referencePicker = false; return true
    }
    private func applyHeadingJump() {
        guard let headingJump, headingJump.pageID == page.id else { return }
        guard page.revision == headingJump.revision else { library.saveError = "Die Seite wurde seit dem Sprungziel geändert."; return }
        preview = false; jumpTo = headingJump.offset
    }

}
private struct WritingFormattingToolbar: View {
    let commands: [WritingToolbarCommand]
    let invoke: (WritingToolbarCommand) -> Void
    var body: some View {
        if !commands.isEmpty {
            ViewThatFits(in: .horizontal) {
                WritingFormattingRow(commands: commands, invoke: invoke).fixedSize(horizontal: true, vertical: false)
                VStack(spacing: 8) {
                    WritingFormattingRow(commands: Array(commands.prefix(2)), invoke: invoke)
                    if commands.count > 2 { WritingFormattingRow(commands: Array(commands.dropFirst(2)), invoke: invoke) }
                }
            }.labelStyle(.iconOnly).buttonStyle(.bordered).controlSize(.large)
                .frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.vertical, 8)
                .background(Color("PaperBase")).accessibilityElement(children: .contain).accessibilityLabel("Text formatieren")
        }
    }
}
private struct WritingFormattingRow: View {
    let commands: [WritingToolbarCommand]
    let invoke: (WritingToolbarCommand) -> Void
    var body: some View {
        HStack(spacing: 12) {
            ForEach(commands, id: \.self) { value in
                Button(value.title, systemImage: value.symbol) { invoke(value) }
                    .accessibilityIdentifier("format-" + value.rawValue)
            }
        }
    }
}
@MainActor @Observable final class KeyboardState {
    private(set) var isVisible = false
    private(set) var height: CGFloat = 0
    @ObservationIgnored private weak var anchor: UIView?
    func attach(_ view: UIView) { anchor = view }
    func detach(_ view: UIView) {
        guard anchor === view else { return }
        anchor = nil; hide()
    }
    private func hasResponder(_ view: UIView) -> Bool {
        view.isFirstResponder || view.subviews.contains(where: hasResponder)
    }
    func apply(endFrame: CGRect, windowBounds: CGRect) {
        let value = KeyboardFrameMath.overlap(endFrame: endFrame, windowBounds: windowBounds)
        if height != value { height = value }
        if isVisible != (value > 0) { isVisible = value > 0 }
    }
    func hide() { apply(endFrame: .null, windowBounds: .null) }
    func handle(_ notification: Notification) {
        guard notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool != false,
              let window = anchor?.window, hasResponder(window),
              let screenFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            hide(); return
        }
        apply(endFrame: window.convert(screenFrame, from: window.screen.coordinateSpace), windowBounds: window.bounds)
    }
}
private struct KeyboardWindowReader: UIViewRepresentable {
    let state: KeyboardState
    func makeCoordinator() -> KeyboardState { state }
    func makeUIView(context: Context) -> UIView {
        let view = UIView(); view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false; state.attach(view); return view
    }
    func updateUIView(_ view: UIView, context: Context) { state.attach(view) }
    static func dismantleUIView(_ view: UIView, coordinator: KeyboardState) { coordinator.detach(view) }
}

struct PageTitleHeader: View {
    @Binding var title: String
    let favorite: Bool
    let focus: Bool
    var body: some View {
        HStack {
            TextField("Ohne Titel", text: $title, axis: .vertical).lineLimit(1...3)
                .font(.system(.title, design: .serif).weight(.semibold)).accessibilityLabel("Seitentitel")
            if favorite { Image(systemName: "star.fill").foregroundStyle(.orange).accessibilityLabel("Favorit") }
        }.padding(.horizontal, 28).padding(.vertical, focus ? 12 : 22).frame(maxWidth: 900)
    }
}
struct WritingStatusBar: View {
    let markdown: String
    let saved: Date?
    let goal: Int
    var body: some View {
        let count = markdown.split(whereSeparator: { $0.isWhitespace }).count
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                WritingCountLabel(count: count, goal: goal)
                if let saved { WritingSavedLabel(saved: saved) }
            }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 4) {
                WritingCountLabel(count: count, goal: goal)
                if let saved { WritingSavedLabel(saved: saved) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 10).background(Color("PaperBase"))
    }
}
private struct WritingCountLabel: View {
    let count: Int
    let goal: Int
    var body: some View {
        Text(goal > 0 ? LocalizedStringResource("\(count) Wörter · Ziel: \(goal)") : LocalizedStringResource("\(count) Wörter"))
    }
}
private struct WritingSavedLabel: View {
    let saved: Date
    var body: some View { Label("Gespeichert \(saved.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle") }
}
struct PageInspector: View {
    let markdown: String
    @Binding var goal: Int
    @Binding var tags: [String]
    let jump: (Int) -> Void
    @State private var tag = ""
    var body: some View {
        Form {
            PageOutlineSection(markdown: markdown, jump: jump)
            Section("Schreibstatistik") {
                LabeledContent("Wörter", value: "\(markdown.split(whereSeparator: { $0.isWhitespace }).count)")
                LabeledContent("Zeichen", value: "\(markdown.count)")
                LabeledContent("Absätze", value: "\(markdown.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count)")
                TextField("Wortziel", value: $goal, format: .number).keyboardType(.numberPad)
                if goal > 0 { ProgressView(value: min(Double(markdown.split(whereSeparator: { $0.isWhitespace }).count) / Double(goal), 1)).accessibilityLabel("Fortschritt zum Wortziel") }
            }
            Section("Schlagwörter") {
                ForEach(tags, id: \.self) { value in
                    HStack { Text(value); Spacer(); Button("Entfernen", systemImage: "minus.circle") { tags.removeAll { $0 == value } }.labelStyle(.iconOnly) }
                }
                HStack {
                    TextField("Neues Schlagwort", text: $tag)
                    Button("Hinzufügen", systemImage: "plus") {
                        let value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty && !tags.contains(value) { tags.append(value); tag = "" }
                    }.labelStyle(.iconOnly)
                }
            }
        }.scrollContentBackground(.hidden).navigationTitle("Seiteninfo")
    }
}
