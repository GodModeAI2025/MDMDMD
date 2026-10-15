import SwiftUI
import UniformTypeIdentifiers

struct MacWritingWorkspace: View {
    @State private var workspace: MacWorkspaceController
    @State private var newSpace = false
    @State private var spaceName = ""
    @State private var shareRouting = MacShareRouting.shared
    @State private var foreground: ICloudForegroundScenes.Lease?
    @State private var libraryColumns = NavigationSplitViewVisibility.all
    @State private var inspectorPresented = false
    @State private var windowWidth: CGFloat = 1280
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    init(library: WritingLibrary) { _workspace = State(initialValue: MacWorkspaceController(library: library)) }
    var body: some View {
        @Bindable var workspace = workspace
        NavigationSplitView(columnVisibility: $libraryColumns) {
            MacLibrarySidebar(workspace: workspace, newSpace: { newSpace = true })
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } content: {
            MacLibraryPageList(workspace: workspace)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            if let id = workspace.selectedPage, let page = workspace.library.currentPage(id) {
                MacPageWritingView(page: page, library: workspace.library, navigation: workspace.navigation, inspectorChanged: { showing in
                    inspectorPresented = showing
                    if showing, windowWidth < 1200 { libraryColumns = .doubleColumn }
                })
                    .id(workspace.library.libraryIdentity.uuidString + id.uuidString)
            } else { MacWritingWelcome(newPage: workspace.newPage) }
        }
        .tint(Color(nsColor: .controlAccentColor))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            windowWidth = width
            if inspectorPresented, width < 1200 { libraryColumns = .doubleColumn }
        }
        .focusedSceneValue(\.macWorkspace, workspace)
        .toolbar {
            ToolbarItem {
                Menu("Dateien", systemImage: "folder") {
                    Button("Markdown importieren …") { if workspace.navigation.prepare() { workspace.importing = true } }
                    Button("Manuskript zusammenstellen …") { if workspace.navigation.prepare() { workspace.showingManuscript = true } }
                    Button("iCloud …") { if workspace.navigation.prepare() { workspace.showingICloud = true } }
                }
            }
        }
        .controlSize(.regular)
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
}

private struct MacWritingWelcome: View {
    let newPage: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 32, weight: .light)).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Raum für deinen nächsten Gedanken")
                    .font(.system(.largeTitle, design: .serif)).multilineTextAlignment(.center)
                Text("Wähle eine Seite in deiner Bibliothek oder beginne mit einem leeren Blatt.")
                    .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button("Neue Seite", systemImage: "plus", action: newPage)
                .buttonStyle(.borderedProminent).controlSize(.large)
            Text("⌘N").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Kurzbefehl: Befehl N")
        }
        .padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PaperSurface() }
        .navigationTitle("Bibliothek")
    }
}
