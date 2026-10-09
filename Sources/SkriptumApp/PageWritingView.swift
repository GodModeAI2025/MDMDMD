import SwiftUI

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
    @State private var editToken: UUID?
    @State private var inspector = false
    @State private var sharedMarkdown: SharedMarkdown?
    @State private var assistant = false
    @State private var preview = false
    @State private var sourceMode = false
    @State private var tools = false
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
    @State private var commandUnavailable = false
    @State private var reviewingQuality = false
    @State private var pendingAIPrompt: String?
    @State private var assistantPrompt = ""
    @State private var assistantRevisionMode = false
    var body: some View {
        VStack(spacing: 0) {
            PageTitleHeader(title: $page.title, favorite: page.favorite, focus: focus)
            Divider()
            if preview {
                MarkdownPreview(title: page.title, markdown: page.markdown, assets: exportAssets)
            } else if !sourceMode {
                BlockWritingView(markdown: $page.markdown, selection: $selection, initialBlocks: library.blocks(for: page.id), preferences: writingPreferences, onBlocksChanged: { blocks in
                    if let (token, revision) = library.updateBlocks(page, blocks: blocks, token: editToken) { editToken = token; page.revision = revision; return true }
                    return false
                }, onPageReference: { if prepareNavigation() { referencePicker = true }; return nil }, onPrompt: { if library.finishTyping(editToken) { editToken = nil; assistant = true } }, onImage: { after in
                    if library.finishTyping(editToken) { editToken = nil; imageAfterBlock = after; insertingImage = true }
                }, onTable: openTable, imageData: { path in
                    guard let attachment = page.attachments?.first(where: { $0.relativePath == path }) else { return nil }
                    return try? library.store?.attachmentData(attachment)
                }, command: command.map { BlockEditorCommand(id: $0.id, prefix: $0.prefix, suffix: $0.suffix) }, onCommandHandled: { command = nil }, jumpToUTF16: jumpTo, onJumpHandled: { jumpTo = nil }, onCommandUnavailable: { commandUnavailable = true }, canonicalBlocks: { library.blocks(for: page.id) })
            } else {
                MarkdownTextEditor(text: $page.markdown, selection: $selection, preferences: writingPreferences, jumpTo: jumpTo, command: command, onCommandHandled: { command = nil }, onJumpHandled: { jumpTo = nil }, onCommandUnavailable: { commandUnavailable = true })
                    .frame(maxWidth: writingPreferences.contentWidth ?? .infinity)
                    .frame(maxWidth: .infinity)
            }
            if !preview { WritingFormattingToolbar(commands: writingPreferences.visibleCommands) { value in command = .init(prefix: value.prefix, suffix: value.suffix) } }
            WritingStatusBar(markdown: page.markdown, saved: library.lastSaved, goal: page.wordGoal)
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
                Button(focus ? "Fokus beenden" : "Fokus", systemImage: focus ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") { focus.toggle() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button(preview ? "Quelltext" : "Vorschau", systemImage: preview ? "chevron.left.forwardslash.chevron.right" : "eye") { if library.finishTyping(editToken) { editToken = nil; do { exportAssets = try library.exportAssets(for: page); preview.toggle() } catch { library.saveError = error.localizedDescription } } }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Assistent", systemImage: "sparkles") { if library.finishTyping(editToken) { editToken = nil; assistantPrompt = ""; assistantRevisionMode = false; assistant = true } }
                Menu("Seitenaktionen", systemImage: "ellipsis.circle") {
                    Button(sourceMode ? "Schreibansicht" : "Markdown-Quelltext", systemImage: "text.alignleft") { if library.finishTyping(editToken) { editToken = nil; sourceMode.toggle(); preview = false } }
                    Button("Seitenregeln, Prompts und Bilder", systemImage: "slider.horizontal.3") { if library.finishTyping(editToken) { editToken = nil; tools = true } }
                    Button("Editor-Einstellungen", systemImage: "textformat") { if prepareNavigation() { loadWritingPreferences(); editorSettings = true } }
                    Button("Anhänge und Verwendung", systemImage: "paperclip") { if prepareNavigation() { attachmentDashboard = true } }
                    Button("Textprüfung und Lektorat", systemImage: "text.badge.checkmark") { if library.finishTyping(editToken) { editToken = nil; reviewingQuality = true } }
                    Button("Verweise und Rückverweise", systemImage: "link") { if library.finishTyping(editToken) { editToken = nil; pageLinks = true } }
                    Menu("Seitenart", systemImage: "doc.text") {
                        Button("Manuskripttext") { changePurpose(.writing) }
                        Button("Recherchematerial") { changePurpose(.material) }
                        Button("Vorlage") { changePurpose(.template) }
                    }.disabled(page.trashed)
                    if let closeLibrary { Button("Zum Dateibrowser", systemImage: "folder", action: closeLibrary) }
                    Button(page.favorite ? "Favorit entfernen" : "Als Favorit markieren", systemImage: "star") { page.favorite.toggle() }
                    Button("Exportieren", systemImage: "square.and.arrow.up") { if library.finishTyping(editToken) { editToken = nil; do { exportPresentation = PageExportPresentation(page: page, assets: try library.exportAssets(for: page), preferenceKey: library.exportPreferenceKey(spaceID: page.spaceID)) } catch { library.saveError = error.localizedDescription } } }
                    Button("Unterseite erstellen", systemImage: "doc.badge.plus", action: createSubpage)
                    Button("Duplizieren", systemImage: "doc.on.doc") {
                        if library.finishTyping(editToken) { editToken = nil; library.duplicatePage(page) }
                    }
                    Button(page.trashed ? "Wiederherstellen" : "In den Papierkorb", systemImage: "trash") { page.trashed.toggle() }
                }
                Button("Gliederung und Statistik", systemImage: "sidebar.right") { if library.finishTyping(editToken) { editToken = nil; inspector.toggle() } }
            }
        }
        .inspector(isPresented: $inspector) {
            VStack(spacing: 0) {
                Picker("Seitenbereich", selection: $inspectorSection) {
                    Text("Seiteninfo").tag(0)
                    Text("Kommentare & Verlauf").tag(1)
                }.pickerStyle(.segmented).padding()
                if inspectorSection == 0 {
                    PageInspector(markdown: page.markdown, goal: $page.wordGoal, tags: $page.tags, jump: {
                        jumpTo = $0; preview = false
                        if horizontalSizeClass == .compact { inspector = false }
                    })
                } else {
                    PageReviewPanel(page: page, selection: selection, library: library, restored: { page = $0 }, beforeMutation: {
                        guard library.finishTyping(editToken) else { return false }
                        editToken = nil; return true
                    })
                }
            }
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .sheet(item: $exportPresentation) { item in ExportOptionsSheet(page: item.page, assets: item.assets, preferenceKey: item.preferenceKey) }
        .sheet(item: $sharedMarkdown) { item in MarkdownShareSheet(url: item.url) }
        .sheet(isPresented: $tools) { PageToolsSheet(page: page, library: library, updated: { page = $0 }) }
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
            if let pendingAIPrompt { assistantPrompt = pendingAIPrompt; self.pendingAIPrompt = nil; assistant = true }
        }) {
            WritingQualitySheet(page: page, library: library, updated: { page = $0 }, aiAction: { prompt, revisionMode in pendingAIPrompt = prompt; assistantRevisionMode = revisionMode; reviewingQuality = false })
        }
        .sheet(isPresented: $insertingImage) { ImageBlockPicker(page: page, library: library, afterBlockID: imageAfterBlock, updated: { page = $0 }) }
        .sheet(item: $tableSession) { item in
            TableEditingSheet(source: item.source, apply: { replacement in
                guard (try? MarkdownTable(replacement)) != nil else { return "Die Tabelle ist kein gültiges rechteckiges Markdown." }
                guard let saved = library.replaceBlock(pageID: item.pageID, baseRevision: item.revision, blockID: item.blockID, expectedSource: item.source, replacement: replacement) else {
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
        .sheet(isPresented: $assistant) {
            AssistantPanel(page: page, selection: selection, library: library, initialPrompt: assistantPrompt, initialRevisionMode: assistantRevisionMode, apply: { markdown, baseRevision in
                guard page.revision == baseRevision else { library.saveError = "Die Seite wurde seit dem KI-Auftrag geändert. Der Vorschlag wurde nicht angewendet."; return }
                page.markdown = markdown
            })
        }
        .onChange(of: page) { previous, changed in
            if let result = library.processEditorNotification(previous: previous, changed: changed, currentDraft: page, token: editToken) {
                editToken = result.token
                if let revision = result.revision { page.revision = revision }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, library.finishTyping(editToken) { editToken = nil }
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
            if library.finishTyping(editToken) { editToken = nil }
        }
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
        guard library.finishTyping(editToken) else { return false }
        editToken = nil
        guard library.persistBeforeNavigation(page, token: nil) else { return false }
        if let latest = library.currentPage(page.id) { page = latest }
        return true
    }
    private func changePurpose(_ purpose: PagePurpose) {
        guard library.finishTyping(editToken) else { return }
        editToken = nil
        if let saved = library.changePurpose(page, purpose: purpose) { page = saved }
    }
    private func insertReference(_ title: String, _ target: PageLinkTarget) -> Bool {
        guard library.resolvePageTarget(target) != nil,
              var current = library.currentPage(page.id), current.revision == page.revision else { library.saveError = "Die Seite wurde inzwischen geändert. Bitte erneut öffnen."; return false }
        let safe = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]").replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        current.markdown += "\n\n[" + safe + "](" + target.url.absoluteString + ")\n"
        guard let revision = library.update(current) else { return false }
        current.revision = revision; page = current; referencePicker = false; return true
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
    struct Heading: Identifiable { let id: Int; let title: String; let level: Int }
    var headings: [Heading] {
        var offset = 0
        return markdown.components(separatedBy: "\n").compactMap { line in
            defer { offset += (line as NSString).length + 1 }
            let level = line.prefix(while: { $0 == "#" }).count
            guard (1...6).contains(level), line.dropFirst(level).first == " " else { return nil }
            return Heading(id: offset, title: String(line.dropFirst(level + 1)), level: level)
        }
    }
    var body: some View {
        Form {
            Section("Gliederung") {
                if headings.isEmpty { Text("Überschriften mit # anlegen").foregroundStyle(.secondary) }
                ForEach(headings) { heading in
                    Button { jump(heading.id) } label: {
                        Text(heading.title).padding(.leading, CGFloat(heading.level - 1) * 10).foregroundStyle(.primary)
                    }
                }
            }
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
        }.navigationTitle("Seiteninfo")
    }
}
