import SwiftUI
import UniformTypeIdentifiers

@main struct SkriptumApp: App {
    @State private var library = WritingLibrary()
    @State private var launch = LibraryLaunchCoordinator()
    var body: some Scene {
        DocumentGroupLaunchScene(Text(" ")) {
            LaunchLibraryAccess(launch: launch)
        } background: {
            LibraryLaunchBackground(library: library, launch: launch)
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
            ExternalMarkdownView(document: document, library: library)
        } makeDocument: { _, _ in MarkdownDocument() }
        WindowGroup("Bibliothek", id: "library") { WritingWorkspace(library: library) }
    }
}

struct WritingWorkspace: View {
    let library: WritingLibrary
    var closeLibrary: (() -> Void)? = nil
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
            List(selection: $selectedPage) {
                ForEach(visiblePages) { page in
                    PageRow(title: page.title, favorite: page.favorite, date: page.modified, child: page.parentID != nil)
                        .tag(page.id)
                        .simultaneousGesture(TapGesture().onEnded { selectedPage = page.id; compactColumn = .detail })
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
            .navigationTitle(library.spaces.first(where: { $0.id == selectedSpace })?.title ?? filter)
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            .toolbar {
                Menu("Dateien", systemImage: "folder") {
                    Button("Manuskript zusammenstellen", systemImage: "books.vertical") { composingManuscript = true }
                    Button("Markdown importieren", systemImage: "square.and.arrow.down") { importing = true }
                    Button("Bibliothekspaket importieren", systemImage: "shippingbox") { importingPackage = true }
                    Button("Bibliothek als Paket teilen", systemImage: "shippingbox.and.arrow.backward") { if let url = library.exportLibraryPackage() { packageShare = SharedMarkdown(url: url) } }
                    NewDocumentButton("Neue Markdown-Datei", source: DocumentCreationSource(id: "markdown"))
                    if let closeLibrary { Button("Zum Dateibrowser", systemImage: "folder", action: closeLibrary) }
                }
                Button("Neue Seite", systemImage: "square.and.pencil") { selectedPage = library.createPage(spaceID: selectedSpace) }
                    .keyboardShortcut("n", modifiers: .command)
            }
        } detail: {
            if let id = selectedPage, let page = library.pages.first(where: { $0.id == id }) {
                PageWritingView(page: page, library: library, focus: $focus, createSubpage: {
                    selectedPage = library.createPage(spaceID: page.spaceID, parentID: page.id)
                }, closeLibrary: closeLibrary)
                .id(id)
            } else {
                ContentUnavailableView("Ein guter Text beginnt hier", systemImage: "pencil.and.outline", description: Text("Wählen Sie eine Seite aus Ihrer Bibliothek oder beginnen Sie mit einem leeren Blatt."))
                    .toolbar { Button("Neue Seite", systemImage: "square.and.pencil") { selectedPage = library.createPage(spaceID: selectedSpace) } }
            }
        }
        .sheet(item: $spaceTools) { SpaceToolsSheet(space: $0, library: library) }
        .sheet(isPresented: $composingManuscript) { ManuscriptExportSheet(library: library, spaceID: selectedSpace) }
        .sheet(item: $packageShare) { MarkdownShareSheet(url: $0.url) }
        .fileImporter(isPresented: $importingPackage, allowedContentTypes: [.folder]) { result in
            do { if library.importLibraryPackage(try result.get()) { selectedSpace = nil; selectedPage = library.pages.first?.id } }
            catch { library.saveError = error.localizedDescription }
        }
        .onChange(of: library.libraryIdentity) { _, _ in selectedSpace = nil; selectedPage = library.pages.first?.id }
        .onChange(of: selectedPage) { _, value in if value != nil { compactColumn = .detail } }
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "scriptum", url.host == "page", let id = UUID(uuidString: url.lastPathComponent), library.pages.contains(where: { $0.id == id }) { selectedPage = id; return .handled }
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
}

struct PageRow: View {
    let title: String
    let favorite: Bool
    let date: Date
    let child: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: child ? "doc.on.doc" : "doc.text").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(title.isEmpty ? "Ohne Titel" : title).font(.headline).lineLimit(2)
                Text(date, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
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
    var body: some View {
        LinearGradient(colors: [Color(red: 0.96, green: 0.94, blue: 0.90), Color(red: 0.94, green: 0.91, blue: 0.86)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .fullScreenCover(isPresented: $launch.presented) {
                WritingWorkspace(library: library, closeLibrary: { launch.presented = false })
            }
    }
}
