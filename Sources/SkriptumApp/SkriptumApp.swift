import SwiftUI
import UniformTypeIdentifiers

@main struct SkriptumApp: App {
    @State private var library = WritingLibrary()
    var body: some Scene {
        DocumentGroupLaunchScene("Skriptum") {
            NewDocumentButton("Neue Markdown-Datei", source: DocumentCreationSource(id: "markdown"))
        } background: {
            LinearGradient(colors: [Color(red: 0.96, green: 0.94, blue: 0.90), Color(red: 0.88, green: 0.84, blue: 0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
        } overlayAccessoryView: { geometry in
            LaunchLibraryAccess(library: library)
                .frame(width: max(180, geometry.frame.width - 40))
                .position(x: geometry.frame.midX, y: geometry.titleViewFrame.maxY + 112)
        }
        DocumentGroup { (document: MarkdownDocument) in
            ExternalMarkdownView(document: document)
        } makeDocument: { _, _ in MarkdownDocument() }
        WindowGroup("Bibliothek", id: "library") { WritingWorkspace(library: library) }
    }
}

struct WritingWorkspace: View {
    let library: WritingLibrary
    @State private var selectedPage: UUID?
    @State private var selectedSpace: UUID?
    @State private var filter = "Alle Seiten"
    @State private var query = ""
    @State private var focus = false
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var newSpace = false
    @State private var spaceName = ""
    @State private var importing = false
    @State private var recovering = false
    var visiblePages: [WritingPage] {
        library.pages.filter {
            ($0.trashed == (filter == "Papierkorb")) &&
            (filter != "Favoriten" || $0.favorite) &&
            (selectedSpace == nil || $0.spaceID == selectedSpace) &&
            (query.isEmpty || $0.title.localizedStandardContains(query) || $0.markdown.localizedStandardContains(query) || $0.tags.contains(where: { $0.localizedStandardContains(query) }))
        }.sorted { $0.modified > $1.modified }
    }
    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List {
                Section("Bibliothek") {
                    ForEach(["Alle Seiten", "Favoriten", "Papierkorb"], id: \.self) { name in
                        Button { filter = name; selectedSpace = nil } label: {
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
                        Button { selectedSpace = space.id; filter = "Alle Seiten" } label: {
                            Label(space.title, systemImage: "folder")
                                .foregroundStyle(selectedSpace == space.id ? Color.accentColor : Color.primary)
                        }
                    }
                    Button("Neuer Space", systemImage: "folder.badge.plus") { newSpace = true }
                }
            }
            .navigationTitle("Skriptum")
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } content: {
            List(selection: $selectedPage) {
                ForEach(visiblePages) { page in
                    PageRow(title: page.title, favorite: page.favorite, date: page.modified, child: page.parentID != nil)
                        .tag(page.id)
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
                Button("Markdown importieren", systemImage: "square.and.arrow.down") { importing = true }
                Button("Neue Seite", systemImage: "square.and.pencil") { selectedPage = library.createPage(spaceID: selectedSpace) }
                    .keyboardShortcut("n", modifiers: .command)
            }
        } detail: {
            if let id = selectedPage, let page = library.pages.first(where: { $0.id == id }) {
                PageWritingView(page: page, library: library, focus: $focus, createSubpage: {
                    selectedPage = library.createPage(spaceID: page.spaceID, parentID: page.id)
                })
                .id(id)
            } else {
                ContentUnavailableView("Ein guter Text beginnt hier", systemImage: "pencil.and.outline", description: Text("Wählen Sie eine Seite aus Ihrer Bibliothek oder beginnen Sie mit einem leeren Blatt."))
                    .toolbar { Button("Neue Seite", systemImage: "square.and.pencil") { selectedPage = library.createPage(spaceID: selectedSpace) } }
            }
        }
        .sheet(isPresented: $recovering) { DraftRecoveryView(library: library, recovered: { selectedPage = $0 }) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .plainText], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for url in urls { if let id = library.importMarkdown(url: url, spaceID: selectedSpace) { selectedPage = id } }
            case .failure(let error): library.saveError = "Import fehlgeschlagen: \(error.localizedDescription)"
            }
        }
        .tint(Color(red: 0.40, green: 0.32, blue: 0.23))
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

struct LaunchLibraryAccess: View {
    let library: WritingLibrary
    @State private var presented = false
    var body: some View {
        Button("Spaces und Bibliothek öffnen", systemImage: "books.vertical") { presented = true }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(red: 0.40, green: 0.32, blue: 0.23))
            .fullScreenCover(isPresented: $presented) {
                WritingWorkspace(library: library)
                    .safeAreaInset(edge: .bottom) {
                        Button("Zum Dateibrowser", systemImage: "folder") { presented = false }
                            .font(.caption).padding(8).frame(maxWidth: .infinity).background(.bar)
                    }
            }
    }
}
