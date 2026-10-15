import SwiftUI
import UniformTypeIdentifiers

struct MacWritingWorkspace: View {
    @State private var workspace: MacWorkspaceController
    @State private var newSpace = false
    @State private var spaceName = ""
    @State private var shareRouting = MacShareRouting.shared
    @State private var foreground: ICloudForegroundScenes.Lease?
    @State private var libraryColumns = NavigationSplitViewVisibility.all
    @State private var columnsBeforeFocus = NavigationSplitViewVisibility.all
    @State private var columnsBeforeInspector: NavigationSplitViewVisibility?
    @State private var inspectorPresented = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    init(library: WritingLibrary) { _workspace = State(initialValue: MacWorkspaceController(library: library)) }
    var body: some View {
        @Bindable var workspace = workspace
        NavigationSplitView(columnVisibility: $libraryColumns) {
            // The library collapses as one native sidebar. Avoid another native
            // split inside it: simultaneous inspector/sidebar transitions can
            // otherwise feed AppKit's constraint pass back into itself.
            HStack(spacing: 0) {
                MacLibrarySidebar(workspace: workspace, newSpace: { newSpace = true })
                    .frame(width: 200)
                Divider()
                MacLibraryPageList(workspace: workspace)
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: .infinity)
            }
            .navigationSplitViewColumnWidth(min: 421, ideal: 461, max: 600)
        } detail: {
            if let id = workspace.selectedPage, let page = workspace.library.currentPage(id) {
                MacPageWritingView(page: page, library: workspace.library, navigation: workspace.navigation,
                    inspector: Binding(get: { inspectorPresented }, set: presentInspector),
                    headingJump: workspace.headingJump, navigate: { workspace.navigate($0) })
                    .id(workspace.library.libraryIdentity.uuidString + id.uuidString)
            } else { MacWritingWelcome(newPage: workspace.newPage) }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Color(nsColor: .controlAccentColor))
        // Library and inspector transitions are explicit. Deriving column
        // visibility from a width changed by those same columns causes a
        // constraint feedback loop during native window resizing.
        .transaction { transaction in transaction.disablesAnimations = true }
        .focusedSceneValue(\.macWorkspace, workspace)
        .onChange(of: workspace.writingFocus) { _, focused in
            if focused {
                columnsBeforeFocus = columnsBeforeInspector ?? libraryColumns
                columnsBeforeInspector = nil
                inspectorPresented = false
                libraryColumns = .detailOnly
            } else {
                libraryColumns = columnsBeforeFocus
                updateInspectorLayout()
            }
        }
        .onChange(of: inspectorPresented) { _, _ in updateInspectorLayout() }
        .onChange(of: workspace.selectedPage) { _, page in
            if page == nil { inspectorPresented = false; workspace.writingFocus = false }
        }
        .onChange(of: libraryColumns) { _, columns in
            if workspace.writingFocus, columns != .detailOnly { workspace.writingFocus = false }
        }
        .controlSize(.regular)
        .safeAreaInset(edge: .bottom) {
            if let error = workspace.library.saveError ?? workspace.library.iCloudShareError ?? shareRouting.failure { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).padding(10).frame(maxWidth: .infinity).background(.regularMaterial) }
        }
        .alert("Neuer Space", isPresented: $newSpace) {
            TextField("Name", text: $spaceName)
            Button("Abbrechen", role: .cancel) { }
            Button("Erstellen") { let title = spaceName.trimmingCharacters(in: .whitespacesAndNewlines); if !title.isEmpty, workspace.navigation.prepare() { workspace.chooseSpace(workspace.library.createSpace(title: title)); spaceName = "" } }
        }
        .fileImporter(isPresented: $workspace.importing, allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .plainText], allowsMultipleSelection: true) { result in
            do { workspace.imported(try result.get()) } catch { workspace.library.saveError = error.localizedDescription }
        }
        .sheet(isPresented: $workspace.importingMarkdownFolder) {
            MarkdownFolderImportSheet(library: workspace.library, spaceID: workspace.spaceID, prepare: { workspace.navigation.prepare() }, imported: { ids in
                if let id = ids.last { _ = workspace.navigate(PageLinkTarget(pageID: id)) }
            })
        }
        .modifier(LocalScheduleForegroundRunner(library: workspace.library))
        .sheet(isPresented: $workspace.showingTasks) { LocalTasksSheet(library: workspace.library).frame(width: 640, height: 680) }
        .sheet(isPresented: $workspace.showingICloud) { ICloudSettingsView(library: workspace.library).frame(width: 580, height: 620) }
        .sheet(isPresented: $workspace.showingShared) { ICloudSharedCatalogView(directory: workspace.library.iCloudStorageDirectory().appendingPathComponent("SharedDocuments")).frame(width: 650, height: 520) }
        .sheet(isPresented: $workspace.showingManuscript) { ManuscriptExportSheet(library: workspace.library, spaceID: workspace.spaceID).frame(width: 680, height: 680) }
        .sheet(isPresented: $workspace.showingTemplates) {
            TemplatePickerSheet(library: workspace.library, targetSpaceID: workspace.spaceID, prepare: workspace.navigation.prepare,
                created: { _ = workspace.navigate(PageLinkTarget(pageID: $0)) }).frame(width: 600, height: 560)
        }
        .sheet(isPresented: $workspace.showingAttachments) {
            AttachmentDashboardSheet(library: workspace.library, navigate: { workspace.navigate(PageLinkTarget(pageID: $0)) }).frame(width: 680, height: 640)
        }
        .environment(\.openURL, OpenURLAction { url in
            if let target = PageLinkTarget(destination: url.absoluteString) {
                _ = workspace.navigate(target); return .handled
            }
            return .systemAction
        })
        .onOpenURL { url in
            if let target = PageLinkTarget(destination: url.absoluteString) { _ = workspace.navigate(target) }
            else if url.isFileURL { workspace.imported([url]) }
        }
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
    private func updateInspectorLayout() {
        guard !workspace.writingFocus else { return }
        if inspectorPresented {
            if columnsBeforeInspector == nil { columnsBeforeInspector = libraryColumns }
            libraryColumns = .detailOnly
        } else if let previous = columnsBeforeInspector {
            columnsBeforeInspector = nil
            libraryColumns = previous
        }
    }
    private func presentInspector(_ showing: Bool) {
        if showing, !workspace.writingFocus {
            if columnsBeforeInspector == nil { columnsBeforeInspector = libraryColumns }
            libraryColumns = .detailOnly
        }
        inspectorPresented = showing
    }
}

private struct MacWritingWelcome: View {
    let newPage: () -> Void
    var body: some View {
        MacManuscriptSurface {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "square.and.pencil")
                    .font(.system(.largeTitle)).foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Raum für deinen nächsten Gedanken")
                        .font(.system(.largeTitle, design: .serif)).fixedSize(horizontal: false, vertical: true)
                    Text("Wähle eine Seite in deiner Bibliothek oder beginne mit einem leeren Blatt.")
                        .font(.body).foregroundStyle(.secondary).lineSpacing(4)
                }
                HStack(spacing: 12) {
                    Button("Neue Seite", systemImage: "plus", action: newPage)
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    Text("⌘N").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Kurzbefehl: Befehl N")
                }
            }
            .frame(maxWidth: 340).padding(36).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Bibliothek")
    }
}

/// Continuous, quiet paper beneath native window controls. The editor owns its
/// readable line width; resizing never replaces its view or editing transaction.
struct MacManuscriptSurface<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Color(nsColor: .textBackgroundColor)
                PaperSurface().opacity(contrast == .increased ? 0 : (scheme == .dark ? 0.28 : 0.48))
            }
    }
}
