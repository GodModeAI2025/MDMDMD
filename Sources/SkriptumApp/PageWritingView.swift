import SwiftUI

struct PageWritingView: View {
    @State private var inspectorSection = 0
    @State var page: WritingPage
    let library: WritingLibrary
    @Binding var focus: Bool
    let createSubpage: () -> Void
    var closeLibrary: (() -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var editToken: UUID?
    @State private var inspector = false
    @State private var sharedMarkdown: SharedMarkdown?
    @State private var assistant = false
    @State private var preview = false
    @State private var sourceMode = false
    @State private var tools = false
    @State private var referencePicker = false
    @State private var insertingImage = false
    @State private var imageAfterBlock: UUID?
    @State private var exportAssets: [String: ExportAsset] = [:]
    @State private var exporting = false
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
                BlockWritingView(markdown: $page.markdown, selection: $selection, initialBlocks: library.blocks(for: page.id), onBlocksChanged: { blocks in
                    if let (token, revision) = library.updateBlocks(page, blocks: blocks, token: editToken) { editToken = token; page.revision = revision; return true }
                    return false
                }, onPageReference: { referencePicker = true; return nil }, onPrompt: { if library.finishTyping(editToken) { editToken = nil; assistant = true } }, onImage: { after in
                    if library.finishTyping(editToken) { editToken = nil; imageAfterBlock = after; insertingImage = true }
                }, imageData: { path in
                    guard let attachment = page.attachments?.first(where: { $0.relativePath == path }) else { return nil }
                    return try? library.store?.attachmentData(attachment)
                }, command: command.map { BlockEditorCommand(id: $0.id, prefix: $0.prefix, suffix: $0.suffix) }, onCommandHandled: { command = nil }, jumpToUTF16: jumpTo, onJumpHandled: { jumpTo = nil }, onCommandUnavailable: { commandUnavailable = true })
            } else {
                MarkdownTextEditor(text: $page.markdown, selection: $selection, jumpTo: jumpTo, command: command, onCommandHandled: { command = nil }, onJumpHandled: { jumpTo = nil }, onCommandUnavailable: { commandUnavailable = true })
                    .frame(maxWidth: focus ? 820 : .infinity)
            }
            if !preview { editingBar }
            WritingStatusBar(markdown: page.markdown, saved: library.lastSaved, goal: page.wordGoal)
        }
        .background(Color(uiColor: .systemBackground))
        .alert("Formatierung hier nicht verfügbar", isPresented: $commandUnavailable) {
            Button("OK", role: .cancel) {}
        } message: { Text("Aktivieren Sie einen Textblock, der diesen Befehl unterstützt. Beenden Sie zunächst eine laufende Texteingabe.") }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(focus ? "Fokus beenden" : "Fokus", systemImage: focus ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") { focus.toggle() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button(preview ? "Quelltext" : "Vorschau", systemImage: preview ? "chevron.left.forwardslash.chevron.right" : "eye") { if library.finishTyping(editToken) { editToken = nil; do { exportAssets = try library.exportAssets(for: page); preview.toggle() } catch { library.saveError = error.localizedDescription } } }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Assistent", systemImage: "sparkles") { if library.finishTyping(editToken) { editToken = nil; assistantPrompt = ""; assistantRevisionMode = false; assistant = true } }
                Menu("Seitenaktionen", systemImage: "ellipsis.circle") {
                    Button(sourceMode ? "Schreibansicht" : "Markdown-Quelltext", systemImage: "text.alignleft") { if library.finishTyping(editToken) { editToken = nil; sourceMode.toggle(); preview = false } }
                    Button("Seitenregeln, Prompts und Bilder", systemImage: "slider.horizontal.3") { if library.finishTyping(editToken) { editToken = nil; tools = true } }
                    Button("Textprüfung und Lektorat", systemImage: "text.badge.checkmark") { if library.finishTyping(editToken) { editToken = nil; reviewingQuality = true } }
                    if let closeLibrary { Button("Zum Dateibrowser", systemImage: "folder", action: closeLibrary) }
                    Button(page.favorite ? "Favorit entfernen" : "Als Favorit markieren", systemImage: "star") { page.favorite.toggle() }
                    Button("Exportieren", systemImage: "square.and.arrow.up") { if library.finishTyping(editToken) { editToken = nil; do { exportAssets = try library.exportAssets(for: page); exporting = true } catch { library.saveError = error.localizedDescription } } }
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
        .sheet(isPresented: $exporting) { ExportOptionsSheet(page: page, assets: exportAssets, preferenceKey: library.exportPreferenceKey(spaceID: page.spaceID)) }
        .sheet(item: $sharedMarkdown) { item in MarkdownShareSheet(url: item.url) }
        .sheet(isPresented: $tools) { PageToolsSheet(page: page, library: library, updated: { page = $0 }) }
        .sheet(isPresented: $reviewingQuality, onDismiss: {
            if let pendingAIPrompt { assistantPrompt = pendingAIPrompt; self.pendingAIPrompt = nil; assistant = true }
        }) {
            WritingQualitySheet(page: page, library: library, updated: { page = $0 }, aiAction: { prompt, revisionMode in pendingAIPrompt = prompt; assistantRevisionMode = revisionMode; reviewingQuality = false })
        }
        .sheet(isPresented: $insertingImage) { ImageBlockPicker(page: page, library: library, afterBlockID: imageAfterBlock, updated: { page = $0 }) }
        .sheet(isPresented: $referencePicker) {
            NavigationStack { List(library.pages.filter { $0.id != page.id && !$0.trashed }) { reference in
                Button(reference.title) {
                    let safeTitle = reference.title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
                    page.markdown += "\n\n[" + safeTitle + "](scriptum://page/" + reference.id.uuidString + ")\n"
                    referencePicker = false
                }
            }.navigationTitle("Seitenverweis").toolbar { Button("Schließen") { referencePicker = false } } }
        }
        .sheet(isPresented: $assistant) {
            AssistantPanel(page: page, selection: selection, library: library, initialPrompt: assistantPrompt, initialRevisionMode: assistantRevisionMode, apply: { markdown, baseRevision in
                guard page.revision == baseRevision else { library.saveError = "Die Seite wurde seit dem KI-Auftrag geändert. Der Vorschlag wurde nicht angewendet."; return }
                page.markdown = markdown
            })
        }
        .onChange(of: page) { previous, changed in
            if !previous.markdown.utf8.elementsEqual(changed.markdown.utf8) {
                if let result = library.updateText(changed, token: editToken) { editToken = result.token; page.revision = result.revision }
            } else if !previous.title.utf8.elementsEqual(changed.title.utf8) || previous.favorite != changed.favorite || previous.tags.count != changed.tags.count || !zip(previous.tags, changed.tags).allSatisfy({ $0.utf8.elementsEqual($1.utf8) }) || previous.trashed != changed.trashed || previous.wordGoal != changed.wordGoal {
                if library.finishTyping(editToken) {
                    editToken = nil
                    if let revision = library.update(changed) { page.revision = revision }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, library.finishTyping(editToken) { editToken = nil }
        }
        .onDisappear {
            library.preserveConflictedDraft(page)
            if library.finishTyping(editToken) { editToken = nil }
        }
    }
    private var editingBar: some View {
        HStack(spacing: 12) {
            Button("Überschrift", systemImage: "textformat.size") { command = .init(prefix: "## ", suffix: "") }
                .accessibilityIdentifier("format-heading")
            Button("Fett", systemImage: "bold") { command = .init(prefix: "**", suffix: "**") }
                .accessibilityIdentifier("format-bold")
            Button("Kursiv", systemImage: "italic") { command = .init(prefix: "*", suffix: "*") }
                .accessibilityIdentifier("format-italic")
            Button("Liste", systemImage: "list.bullet") { command = .init(prefix: "- ", suffix: "") }
                .accessibilityIdentifier("format-list")
        }.labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20).padding(.vertical, 8)
            .background(.bar)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Text formatieren")
    }
}
struct PageTitleHeader: View {
    @Binding var title: String
    let favorite: Bool
    let focus: Bool
    var body: some View {
        HStack {
            TextField("Ohne Titel", text: $title).font(.system(.title, design: .serif).weight(.semibold)).accessibilityLabel("Seitentitel")
            if favorite { Image(systemName: "star.fill").foregroundStyle(.orange).accessibilityLabel("Favorit") }
        }.padding(.horizontal, 28).padding(.vertical, focus ? 12 : 22).frame(maxWidth: 900)
    }
}
struct WritingStatusBar: View {
    let markdown: String
    let saved: Date?
    let goal: Int
    var body: some View {
        HStack {
            Text("\(markdown.split(whereSeparator: { $0.isWhitespace }).count) Wörter")
            if goal > 0 { Text("Ziel: \(goal)") }
            Spacer()
            if let saved { Label("Gespeichert \(saved.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle") }
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
    }
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
