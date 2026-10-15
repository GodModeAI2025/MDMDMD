import SwiftUI
import AppKit

private enum MacLibraryLocation: Hashable {
    case all, favorites, trash, space(UUID)
}

struct MacLibrarySidebar: View {
    let workspace: MacWorkspaceController
    let newSpace: () -> Void
    private var location: Binding<MacLibraryLocation?> {
        Binding(get: {
            if let id = workspace.spaceID { return .space(id) }
            return workspace.filter == "Favoriten" ? .favorites : workspace.filter == "Papierkorb" ? .trash : .all
        }, set: { value in
            guard let value, workspace.navigation.prepare() else { return }
            switch value {
            case .all: workspace.chooseSpace(nil)
            case .favorites: workspace.chooseSpace(nil); workspace.filter = "Favoriten"
            case .trash: workspace.chooseSpace(nil); workspace.filter = "Papierkorb"
            case .space(let id): workspace.chooseSpace(id)
            }
        })
    }
    var body: some View {
        VStack(spacing: 0) {
            MacLibraryBrand()
            List(selection: location) {
                Section("Bibliothek") {
                    Label("Alle Seiten", systemImage: "doc.text").badge(workspace.library.pages.filter { !$0.trashed }.count).tag(MacLibraryLocation.all)
                    Label("Favoriten", systemImage: "star").badge(workspace.library.pages.filter { !$0.trashed && $0.favorite }.count).tag(MacLibraryLocation.favorites)
                    Label("Papierkorb", systemImage: "trash").badge(workspace.library.pages.filter(\.trashed).count).tag(MacLibraryLocation.trash)
                }
                Section {
                    ForEach(workspace.library.spaces) { space in
                        Label(space.title, systemImage: "folder").tag(MacLibraryLocation.space(space.id))
                    }
                    Button("Neuer Space", systemImage: "folder.badge.plus", action: newSpace)
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                } header: { Text("Spaces") }
                Section("Zusammenarbeit") {
                    Button("iCloud", systemImage: "icloud") { if workspace.navigation.prepare() { workspace.showingICloud = true } }.buttonStyle(.plain)
                    Button("Geteilte Dokumente", systemImage: "person.2") { if workspace.navigation.prepare() { workspace.showingShared = true } }.buttonStyle(.plain)
                }
            }.listStyle(.sidebar).font(.callout).symbolRenderingMode(.hierarchical).scrollContentBackground(.hidden)
        }.background { Color(nsColor: .windowBackgroundColor); PaperSurface().opacity(0.09) }
    }
}

private struct MacLibraryBrand: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PressedScriptumWordmark().frame(width: 104, height: 28)
            Text("Schreibbibliothek").font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)
    }
}

private struct MacPageListEntry: Identifiable {
    let id: UUID
    let title: String
    let preview: String
    let modified: Date
    let favorite: Bool
    let purpose: PagePurpose
}

struct MacLibraryPageList: View {
    let workspace: MacWorkspaceController
    @State private var entries: [MacPageListEntry] = []
    private var title: String { workspace.spaceID.flatMap { id in workspace.library.spaces.first { $0.id == id }?.title } ?? workspace.filter }
    var body: some View {
        @Bindable var workspace = workspace
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.title3).fontWeight(.semibold).lineLimit(2)
                        Group {
                            if entries.count == 1 { Text("1 Seite") }
                            else { Text("\(entries.count, format: .number) Seiten") }
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Neue Seite", systemImage: "square.and.pencil") { workspace.newPage() }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).controlSize(.large).help("Neue Seite (⌘N)")
                }
                MacLibrarySearch(query: $workspace.query)
            }.padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 16)
            Divider().opacity(0.5).padding(.horizontal, 16)
            List(selection: $workspace.selectedPage) {
                ForEach(entries) { entry in
                    MacLibraryPageRow(entry: entry).tag(entry.id)
                        .contextMenu {
                            Button(entry.favorite ? "Favorit entfernen" : "Als Favorit markieren") { change(entry.id) { $0.favorite.toggle() } }
                            Button(workspace.filter == "Papierkorb" ? "Wiederherstellen" : "In den Papierkorb") { change(entry.id) { $0.trashed.toggle() } }
                            Button("Duplizieren") {
                                if workspace.navigation.prepare(), let page = workspace.library.currentPage(entry.id) { workspace.selectedPage = workspace.library.duplicatePage(page) }
                            }
                        }
                }
            }.listStyle(.inset).scrollContentBackground(.hidden)
                // Recreate the native list when an empty page gains its first preview.
                // macOS can otherwise retain the insertion cell's smaller cached height.
                .id(entries.map { $0.id.uuidString + ($0.preview.isEmpty ? ":empty" : ":text") })
                .overlay {
                    if entries.isEmpty {
                        ContentUnavailableView("Keine Seiten", systemImage: "doc.text", description: Text("Beginne mit einer neuen Seite oder ändere die Suche."))
                    }
                }
        }
        .background { Color(nsColor: .textBackgroundColor); PaperSurface().opacity(0.08) }
        .navigationTitle(title)
        .onAppear(perform: refresh)
        .onChange(of: workspace.library.pages) { _, _ in refresh() }
        .onChange(of: workspace.spaceID) { _, _ in refresh() }
        .onChange(of: workspace.filter) { _, _ in refresh() }
        .onChange(of: workspace.query) { _, _ in refresh() }
    }
    private func refresh() {
        entries = workspace.library.pages.filter { page in
            page.trashed == (workspace.filter == "Papierkorb") &&
            (workspace.filter != "Favoriten" || page.favorite) &&
            (workspace.spaceID == nil || page.spaceID == workspace.spaceID) &&
            (workspace.query.isEmpty || page.title.localizedStandardContains(workspace.query) || page.markdown.localizedStandardContains(workspace.query) || page.tags.contains { $0.localizedStandardContains(workspace.query) })
        }.sorted { $0.modified > $1.modified }.map { page in
            let excerpt = page.markdown.prefix(500).split(separator: "\n").filter { !$0.hasPrefix("#") }.joined(separator: " ")
            return MacPageListEntry(id: page.id, title: page.title, preview: String(((try? AttributedString(markdown: String(excerpt.prefix(180)), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(String(excerpt.prefix(180)))).characters), modified: page.modified, favorite: page.favorite, purpose: page.effectivePurpose)
        }
    }
    private func change(_ id: UUID, mutation: (inout WritingPage) -> Void) {
        guard workspace.navigation.prepare(), var current = workspace.library.currentPage(id) else { return }
        mutation(&current); workspace.library.update(current)
    }
}

private struct MacLibrarySearch: View {
    @Binding var query: String
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Seiten durchsuchen", text: $query).textFieldStyle(.plain).accessibilityLabel("Seiten durchsuchen")
            if !query.isEmpty {
                Button("Suche löschen", systemImage: "xmark.circle.fill") { query = "" }.labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }.font(.callout).padding(.horizontal, 9).padding(.vertical, 7)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct MacLibraryPageRow: View {
    let entry: MacPageListEntry
    @Environment(\.backgroundProminence) private var prominence
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title.isEmpty ? "Ohne Titel" : entry.title).font(.headline).lineLimit(2)
                if entry.favorite { Image(systemName: "star.fill").font(.caption).accessibilityLabel("Favorit") }
            }
            Group {
                if entry.preview.isEmpty { Text("Leeres Blatt") }
                else { Text(entry.preview) }
            }.font(.caption).foregroundStyle(prominence == .increased ? .primary : .secondary).lineSpacing(2).lineLimit(2, reservesSpace: true)
            HStack {
                Text(entry.modified, format: .dateTime.day().month(.abbreviated)).font(.caption2)
                if entry.purpose != .writing {
                    Text(entry.purpose == .material ? LocalizedStringKey("Material") : LocalizedStringKey("Vorlage")).font(.caption2)
                }
            }.foregroundStyle(prominence == .increased ? .primary : .secondary)
        }.padding(.vertical, 9).frame(minHeight: 82, alignment: .topLeading).frame(maxWidth: .infinity, alignment: .leading)
    }
}
