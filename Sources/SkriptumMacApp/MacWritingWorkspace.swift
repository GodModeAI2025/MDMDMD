import SwiftUI
import UniformTypeIdentifiers

struct MacWritingWorkspace: View {
    @State private var workspace: MacWorkspaceController
    @State private var newSpace = false
    @State private var spaceName = ""
    @State private var shareRouting = MacShareRouting.shared
    @State private var foreground: ICloudForegroundScenes.Lease?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    init(library: WritingLibrary) { _workspace = State(initialValue: MacWorkspaceController(library: library)) }
    private var visiblePages: [WritingPage] {
        workspace.library.pages.filter { page in
            page.trashed == (workspace.filter == "Papierkorb") &&
            (workspace.filter != "Favoriten" || page.favorite) &&
            (workspace.spaceID == nil || page.spaceID == workspace.spaceID) &&
            (workspace.query.isEmpty || page.title.localizedStandardContains(workspace.query) || page.markdown.localizedStandardContains(workspace.query) || page.tags.contains { $0.localizedStandardContains(workspace.query) })
        }.sorted { $0.modified > $1.modified }
    }
    var body: some View {
        @Bindable var workspace = workspace
        NavigationSplitView {
            List {
                Section("Bibliothek") {
                    ForEach(["Alle Seiten", "Favoriten", "Papierkorb"], id: \.self) { name in
                        Button { if workspace.navigation.prepare() { workspace.spaceID = nil; workspace.filter = name; workspace.selectedPage = nil } } label: {
                            Label(name, systemImage: name == "Favoriten" ? "star" : name == "Papierkorb" ? "trash" : "books.vertical")
                        }.buttonStyle(.plain).padding(.vertical, 4)
                    }
                }
                Section("Spaces") {
                    ForEach(workspace.library.spaces) { space in
                        Button { workspace.chooseSpace(space.id) } label: { Label(space.title, systemImage: "folder") }.buttonStyle(.plain).padding(.vertical, 4)
                    }
                    Button("Neuer Space", systemImage: "folder.badge.plus") { newSpace = true }.buttonStyle(.plain)
                }
                Section {
                    Button("iCloud", systemImage: "icloud") { if workspace.navigation.prepare() { workspace.showingICloud = true } }.buttonStyle(.plain)
                    Button("Geteilte Dokumente", systemImage: "person.2") { if workspace.navigation.prepare() { workspace.showingShared = true } }.buttonStyle(.plain)
                }
            }.listStyle(.sidebar).scrollContentBackground(.hidden).background { PaperSurface() }
                .safeAreaInset(edge: .top) { ScriptumPaperBrand(compact: true).padding() }
                .navigationSplitViewColumnWidth(min: 190, ideal: 225)
        } content: {
            List(selection: $workspace.selectedPage) {
                ForEach(visiblePages) { page in
                    MacPageRow(title: page.title, modified: page.modified, favorite: page.favorite, purpose: page.effectivePurpose)
                        .tag(page.id)
                        .contextMenu {
                            Button(page.favorite ? "Favorit entfernen" : "Als Favorit markieren") { change(page) { $0.favorite.toggle() } }
                            Button(page.trashed ? "Wiederherstellen" : "In den Papierkorb") { change(page) { $0.trashed.toggle() } }
                            Button("Duplizieren") { if workspace.navigation.prepare() { workspace.selectedPage = workspace.library.duplicatePage(page) } }
                        }
                }
            }.scrollContentBackground(.hidden).background { PaperSurface() }
                .searchable(text: $workspace.query, prompt: "Titel, Text und Schlagwörter")
                .navigationTitle(workspace.spaceID.flatMap { id in workspace.library.spaces.first { $0.id == id }?.title } ?? workspace.filter)
                .navigationSplitViewColumnWidth(min: 220, ideal: 270)
                .overlay { if visiblePages.isEmpty { ContentUnavailableView("Keine Seiten", systemImage: "doc.text", description: Text("Beginne mit einer neuen Seite oder ändere die Suche.")) } }
        } detail: {
            if let id = workspace.selectedPage, let page = workspace.library.currentPage(id) {
                MacPageWritingView(page: page, library: workspace.library, navigation: workspace.navigation)
                    .id(workspace.library.libraryIdentity.uuidString + id.uuidString)
            } else { ContentUnavailableView("Ein guter Text beginnt hier", systemImage: "pencil.and.outline", description: Text("Wähle eine Seite oder beginne mit einem leeren Blatt.")) }
        }
        .background { PaperSurface().ignoresSafeArea() }
        .focusedSceneValue(\.macWorkspace, workspace)
        .toolbar {
            ToolbarItem { Button("Neue Seite", systemImage: "square.and.pencil") { workspace.newPage() } }
            ToolbarItem {
                Menu("Dateien", systemImage: "folder") {
                    Button("Markdown importieren …") { if workspace.navigation.prepare() { workspace.importing = true } }
                    Button("Manuskript zusammenstellen …") { if workspace.navigation.prepare() { workspace.showingManuscript = true } }
                    Button("iCloud …") { if workspace.navigation.prepare() { workspace.showingICloud = true } }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let error = workspace.library.saveError ?? shareRouting.failure { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).padding(10).frame(maxWidth: .infinity).background(.regularMaterial) }
        }
        .alert("Neuer Space", isPresented: $newSpace) {
            TextField("Name", text: $spaceName)
            Button("Abbrechen", role: .cancel) { }
            Button("Erstellen") { let title = spaceName.trimmingCharacters(in: .whitespacesAndNewlines); if !title.isEmpty, workspace.navigation.prepare() { workspace.chooseSpace(workspace.library.createSpace(title: title)); spaceName = "" } }
        }
        .fileImporter(isPresented: $workspace.importing, allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .plainText], allowsMultipleSelection: true) { result in
            do { workspace.imported(try result.get()) } catch { workspace.library.saveError = error.localizedDescription }
        }
        .sheet(isPresented: $workspace.showingICloud) { ICloudSettingsView(library: workspace.library).frame(width: 580, height: 620) }
        .sheet(isPresented: $workspace.showingShared) { ICloudSharedCatalogView(directory: workspace.library.iCloudStorageDirectory().appendingPathComponent("SharedDocuments")).frame(width: 650, height: 520) }
        .sheet(isPresented: $workspace.showingManuscript) { ManuscriptExportSheet(library: workspace.library, spaceID: workspace.spaceID).frame(width: 680, height: 680) }
        .onOpenURL { workspace.imported([$0]) }
        .task {
            workspace.library.reload()
            let token = workspace.library.iCloudForegroundScenes.register(); foreground = token
            token.update(active: scenePhase == .active)
            let session = workspace.library.iCloudSession ?? ICloudLibrarySession(library: workspace.library)
            workspace.library.iCloudSession = session
            session.setForegroundActive(workspace.library.iCloudForegroundScenes.isActive)
            await session.resumeSavedConnection()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { _ = workspace.navigation.prepare() }
            foreground?.update(active: phase == .active)
            workspace.library.iCloudSession?.setForegroundActive(workspace.library.iCloudForegroundScenes.isActive)
        }
        .onDisappear { _ = workspace.navigation.prepare(); foreground?.close(); workspace.library.iCloudSession?.setForegroundActive(workspace.library.iCloudForegroundScenes.isActive) }
        .onChange(of: shareRouting.pending) { _, _ in if let identity = shareRouting.claim() { openWindow(id: "shared-document", value: identity) } }
    }
    private func change(_ page: WritingPage, mutation: (inout WritingPage) -> Void) {
        guard workspace.navigation.prepare(), var current = workspace.library.currentPage(page.id) else { return }
        mutation(&current); workspace.library.update(current)
    }
}
private struct MacPageRow: View {
    let title: String
    let modified: Date
    let favorite: Bool
    let purpose: PagePurpose
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(title.isEmpty ? "Ohne Titel" : title).font(.headline).lineLimit(2); if favorite { Image(systemName: "star.fill").accessibilityLabel("Favorit") } }
            if purpose != .writing { Text(purpose == .material ? "Material" : "Vorlage").font(.caption).foregroundStyle(.secondary) }
            Text(modified, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 7)
    }
}
