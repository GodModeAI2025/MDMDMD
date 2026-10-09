import SwiftUI
import UniformTypeIdentifiers

@main struct SkriptumApp: App {
    @State private var library = WritingLibrary()
    @State private var launch = LibraryLaunchCoordinator()
    var body: some Scene {
        DocumentGroupLaunchScene(Text(" ")) {
            LaunchLibraryAccess(launch: launch)
        } background: {
            LibraryLaunchBackground(library: library, launch: launch, libraryActivated: { library = $0 })
        } overlayAccessoryView: { geometry in
            Image("ScriptumWordmark")
                .resizable()
                .scaledToFit()
                .frame(width: min(max(geometry.frame.width - 40, 160), 500), height: 120)
                .position(x: geometry.frame.midX, y: geometry.titleViewFrame.minY + 90)
                .allowsHitTesting(false)
                .accessibilityLabel("Scriptum")
        }
        DocumentGroup { (document: MarkdownDocument) in
            ExternalMarkdownView(document: document, library: library, libraryActivated: { library = $0 })
        } makeDocument: { _, _ in MarkdownDocument() }
        WindowGroup("Bibliothek", id: "library") { WritingWorkspace(library: library, libraryActivated: { library = $0 }) }
    }
}

struct WritingWorkspace: View {
    @State var library: WritingLibrary
    var closeLibrary: (() -> Void)? = nil
    var libraryActivated: ((WritingLibrary) -> Void)? = nil
    @State private var selectedPage: UUID?
    @State private var selectedSpace: UUID?
    @State private var filter = "Alle Seiten"
    @State private var query = ""
    @State private var focus = false
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var compactColumn: NavigationSplitViewColumn = .content
    @State private var newSpace = false
    @State private var spaceName = ""
    @State private var importing = false
    @State private var recovering = false
    @State private var importingPackage = false
    @State private var packageShare: SharedMarkdown?
    @State private var spaceTools: WritingSpace?
    @State private var composingManuscript = false
    @State private var navigationGuard = EditorNavigationGuard()
    @State private var navigationHistory: PageNavigationHistory?
    @State private var headingJump: WritingHeadingJump?
    @State private var templatePicker = false
    var visiblePages: [WritingPage] {
        library.pages.filter {
            ($0.trashed == (filter == "Papierkorb")) &&
            (filter != "Favoriten" || $0.favorite) &&
            (selectedSpace == nil || $0.spaceID == selectedSpace) &&
            (query.isEmpty || $0.title.localizedStandardContains(query) || $0.markdown.localizedStandardContains(query) || $0.tags.contains(where: { $0.localizedStandardContains(query) }))
        }.sorted { $0.modified > $1.modified }
    }
    var body: some View {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
            List {
                Section("Bibliothek") {
                    ForEach(["Alle Seiten", "Favoriten", "Papierkorb"], id: \.self) { name in
                        Button { filter = name; selectedSpace = nil; compactColumn = .content } label: {
                            Label(name, systemImage: name == "Favoriten" ? "star" : name == "Papierkorb" ? "trash" : "books.vertical")
                                .foregroundStyle(filter == name && selectedSpace == nil ? Color.accentColor : Color.primary)
                        }
                    }
                }
                Section {
                    Button("Wiederherstellungen", systemImage: "arrow.counterclockwise") { recovering = true }
                        .badge(library.recoveries.count)
                }
                Section("Spaces") {
                    ForEach(library.spaces) { space in
                        Button { selectedSpace = space.id; filter = "Alle Seiten"; compactColumn = .content } label: {
                            Label(space.title, systemImage: "folder")
                                .foregroundStyle(selectedSpace == space.id ? Color.accentColor : Color.primary)
                        }.contextMenu { Button("Regeln und Prompts") { spaceTools = space } }
                    }
                    Button("Neuer Space", systemImage: "folder.badge.plus") { newSpace = true }
                }
            }
            .navigationTitle("Scriptum")
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } content: {
            List {
                ForEach(visiblePages) { page in
                    Button { _ = navigate(PageLinkTarget(pageID: page.id), allowTrashed: page.trashed) } label: {
                        PageRow(title: page.title, favorite: page.favorite, date: page.modified, child: page.parentID != nil, purpose: page.effectivePurpose)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .listRowBackground(selectedPage == page.id ? Color.accentColor.opacity(0.1) : Color.clear)
                        .contextMenu {
                            Button(page.favorite ? "Favorit entfernen" : "Als Favorit markieren", systemImage: "star") {
                                var changed = page; changed.favorite.toggle(); library.update(changed)
                            }
                            Button(page.trashed ? "Wiederherstellen" : "In den Papierkorb", systemImage: page.trashed ? "arrow.uturn.backward" : "trash") {
                                var changed = page; changed.trashed.toggle(); library.update(changed)
                            }
                        }
                }
            }
            .overlay { if visiblePages.isEmpty { ContentUnavailableView("Keine Seiten", systemImage: "doc.text.magnifyingglass", description: Text("Erstellen Sie eine Seite oder ändern Sie Ihre Suche.")) } }
            .searchable(text: $query, prompt: "Titel und Text durchsuchen")
            .safeAreaInset(edge: .bottom) { ManuscriptCountFooter(library: library, spaceID: selectedSpace) }
            .navigationTitle(filter == "Papierkorb" ? filter : library.spaces.first(where: { $0.id == selectedSpace })?.title ?? filter)
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            .toolbar {
                Menu("Dateien", systemImage: "folder") {
                    Button("Manuskript zusammenstellen", systemImage: "books.vertical") { composingManuscript = true }
                    Button("Aus Vorlage erstellen", systemImage: "doc.on.doc") { templatePicker = true }
                    Button("Markdown importieren", systemImage: "square.and.arrow.down") { importing = true }
                    Button("Bibliothekspaket importieren", systemImage: "shippingbox") { importingPackage = true }
                    Button("Bibliothek als Paket teilen", systemImage: "shippingbox.and.arrow.backward") { if let url = library.exportLibraryPackage() { packageShare = SharedMarkdown(url: url) } }
                    NewDocumentButton("Neue Markdown-Datei", source: DocumentCreationSource(id: "markdown"))
                    if let closeLibrary { Button("Zum Dateibrowser", systemImage: "folder", action: closeLibrary) }
                }
                Button("Neue Seite", systemImage: "square.and.pencil") { createPage(spaceID: selectedSpace) }
                    .keyboardShortcut("n", modifiers: .command)
            }
        } detail: {
            if let id = selectedPage, let page = library.pages.first(where: { $0.id == id }) {
                PageWritingView(page: page, library: library, focus: $focus, createSubpage: {
                    createPage(spaceID: page.spaceID, parentID: page.id)
                }, closeLibrary: closeLibrary, navigationGuard: navigationGuard, navigate: { navigate($0) }, headingJump: headingJump, canGoBack: navigationHistory?.backCandidate != nil, canGoForward: navigationHistory?.forwardCandidate != nil, goBack: { moveInHistory(back: true) }, goForward: { moveInHistory(back: false) })
                .id(library.libraryIdentity.uuidString + ":" + id.uuidString)
            } else {
                ContentUnavailableView("Ein guter Text beginnt hier", systemImage: "pencil.and.outline", description: Text("Wählen Sie eine Seite aus Ihrer Bibliothek oder beginnen Sie mit einem leeren Blatt."))
                    .toolbar { Button("Neue Seite", systemImage: "square.and.pencil") { createPage(spaceID: selectedSpace) } }
            }
        }
        .sheet(item: $spaceTools) { SpaceToolsSheet(space: $0, library: library) }
        .sheet(isPresented: $templatePicker) { TemplatePickerSheet(library: library, targetSpaceID: selectedSpace, prepare: { navigationGuard.prepare() }, created: { _ = navigate(PageLinkTarget(pageID: $0)) }) }
        .sheet(isPresented: $composingManuscript) { ManuscriptExportSheet(library: library, spaceID: selectedSpace) }
        .sheet(item: $packageShare) { MarkdownShareSheet(url: $0.url) }
        .fileImporter(isPresented: $importingPackage, allowedContentTypes: [.folder]) { result in
            do {
                if let imported = library.importLibraryPackage(try result.get()) {
                    library = imported; libraryActivated?(imported)
                    selectedSpace = nil; selectedPage = imported.pages.first?.id
                }
            }
            catch { library.saveError = error.localizedDescription }
        }
        .onChange(of: library.libraryIdentity) { _, _ in navigationHistory = PageNavigationHistory(libraryID: library.libraryIdentity); headingJump = nil; selectedSpace = nil; selectedPage = library.pages.first?.id }
        .onChange(of: selectedPage) { _, value in
            if let value {
                compactColumn = .detail
                if navigationHistory?.libraryID != library.libraryIdentity { navigationHistory = PageNavigationHistory(libraryID: library.libraryIdentity) }
                if navigationHistory?.current?.pageID != value { navigationHistory?.visit(PageNavigationLocation(pageID: value)) }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme?.lowercased() == "scriptum" {
                guard let target = PageLinkTarget(destination: url.absoluteString) else { library.saveError = "Dieser interne Verweis ist ungültig."; return .discarded }
                _ = navigate(target); return .handled
            }
            return .systemAction
        })
        .sheet(isPresented: $recovering) { DraftRecoveryView(library: library, recovered: { selectedPage = $0 }) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .plainText], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for url in urls { if let id = library.importMarkdown(url: url, spaceID: selectedSpace) { selectedPage = id } }
            case .failure(let error): library.saveError = "Import fehlgeschlagen: \(error.localizedDescription)"
            }
        }
        .tint(Color(red: 0.10, green: 0.17, blue: 0.25))
        .onChange(of: focus) { _, value in columns = value ? .detailOnly : .all }
        .task { if selectedPage == nil { selectedPage = library.pages.first(where: { !$0.trashed })?.id } }
        .alert("Neuer Space", isPresented: $newSpace) {
            TextField("Name", text: $spaceName)
            Button("Erstellen") {
                let name = spaceName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { selectedSpace = library.createSpace(title: name); spaceName = "" }
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .safeAreaInset(edge: .bottom) {
            if let error = library.saveError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).padding().background(.regularMaterial)
            }
        }
    }
    @discardableResult private func navigate(_ target: PageLinkTarget, record: Bool = true, allowTrashed: Bool = false) -> Bool {
        guard navigationGuard.prepare(), let resolved = library.resolvePageTarget(target, allowTrashed: allowTrashed) else { return false }
        if navigationHistory?.libraryID != library.libraryIdentity { navigationHistory = PageNavigationHistory(libraryID: library.libraryIdentity) }
        if record { navigationHistory?.visit(PageNavigationLocation(pageID: target.pageID, heading: target.heading)) }
        headingJump = resolved.offset.map { WritingHeadingJump(pageID: resolved.page.id, revision: resolved.page.revision, offset: $0) }
        selectedPage = resolved.page.id; selectedSpace = resolved.page.spaceID; filter = resolved.page.trashed ? "Papierkorb" : "Alle Seiten"; query = ""; compactColumn = .detail
        return true
    }
    private func moveInHistory(back: Bool) {
        guard let candidate = back ? navigationHistory?.backCandidate : navigationHistory?.forwardCandidate else { return }
        guard navigate(PageLinkTarget(pageID: candidate.pageID, heading: candidate.heading), record: false) else { return }
        if back { _ = navigationHistory?.commitBack(to: candidate) } else { _ = navigationHistory?.commitForward(to: candidate) }
    }
    private func createPage(spaceID: UUID?, parentID: UUID? = nil) {
        guard navigationGuard.prepare(), let id = library.createPage(spaceID: spaceID, parentID: parentID) else { return }
        _ = navigate(PageLinkTarget(pageID: id))
    }
}

struct PageRow: View {
    let title: String
    let favorite: Bool
    let date: Date
    let child: Bool
    var purpose: PagePurpose = .writing
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: purpose == .material ? "paperclip" : purpose == .template ? "doc.on.doc" : child ? "doc.on.doc" : "doc.text").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(title.isEmpty ? "Ohne Titel" : title).font(.headline).lineLimit(2)
                Text(date, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                if purpose != .writing { Text(purpose == .material ? "Recherchematerial" : "Vorlage").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if favorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.orange).accessibilityLabel("Favorit") }
        }.padding(.vertical, 5)
    }
}

@MainActor @Observable final class LibraryLaunchCoordinator {
    var presented = false
}

struct LaunchLibraryAccess: View {
    let launch: LibraryLaunchCoordinator
    var body: some View {
        Button("Spaces und Bibliothek öffnen", systemImage: "books.vertical") { launch.presented = true }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(red: 0.10, green: 0.17, blue: 0.25))
    }
}

struct LibraryLaunchBackground: View {
    let library: WritingLibrary
    @Bindable var launch: LibraryLaunchCoordinator
    var libraryActivated: ((WritingLibrary) -> Void)? = nil
    var body: some View {
        LinearGradient(colors: [Color(red: 0.96, green: 0.94, blue: 0.90), Color(red: 0.94, green: 0.91, blue: 0.86)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .fullScreenCover(isPresented: $launch.presented) {
                WritingWorkspace(library: library, closeLibrary: { launch.presented = false }, libraryActivated: libraryActivated)
            }
    }
}
