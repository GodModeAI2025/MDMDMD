import SwiftUI

private struct LinkDisplayRow: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let target: PageLinkTarget?
}

struct PageLinksSheet: View {
    let pageID: UUID
    let library: WritingLibrary
    let navigate: (PageLinkTarget) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var outgoing: [LinkDisplayRow] = []
    @State private var incoming: [LinkDisplayRow] = []
    @State private var loading = true
    private var snapshotKey: String { library.pages.map { $0.id.uuidString + $0.revision.uuidString }.joined() }
    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView("Verweise werden gelesen …") }
                PageLinkSection(title: "Verweise dieser Seite", rows: outgoing, open: open)
                PageLinkSection(title: "Rückverweise", rows: incoming, open: open)
            }
            .navigationTitle("Seitenverweise")
            .toolbar { Button("Schließen") { dismiss() } }
            .task(id: snapshotKey) {
                loading = true
                guard let store = library.store, let source = store.snapshot.pages.first(where: { $0.id == pageID }) else { loading = false; return }
                let pages = store.snapshot.pages, scope = Set(store.snapshot.spaces.map(\.id)), identity = library.libraryIdentity
                let result = await Task.detached(priority: .userInitiated) {
                    let index = PageLinkIndex(libraryID: identity, spaceID: source.spaceID, pages: pages, readableSpaceIDs: scope)
                    let names = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0.title) })
                    let out = index.links(from: pageID).enumerated().map { ordinal, link -> LinkDisplayRow in
                        let state = index.resolve(link.target)
                        let valid: Bool
                        let detail: String
                        switch state {
                        case .resolved(_, let heading): valid = true; detail = heading?.title ?? names[link.target.pageID] ?? "Seite"
                        case .missingPage: valid = false; detail = "Zielseite fehlt"
                        case .trashed: valid = false; detail = "Ziel liegt im Papierkorb"
                        case .outsideSpace: valid = false; detail = "Ziel ist nicht freigegeben"
                        case .missingHeading: valid = false; detail = "Überschrift nicht mehr vorhanden"
                        case .ambiguousPage: valid = false; detail = "Ziel ist nicht eindeutig"
                        }
                        return LinkDisplayRow(id: source.revision.uuidString + ":out:" + String(ordinal), title: link.label, detail: detail, target: valid ? link.target : nil)
                    }
                    let back = index.backlinks(to: pageID).enumerated().map { ordinal, link in
                        LinkDisplayRow(id: link.sourceRevision.uuidString + ":back:" + link.sourcePageID.uuidString + ":" + String(ordinal), title: names[link.sourcePageID] ?? "Seite", detail: link.label, target: PageLinkTarget(pageID: link.sourcePageID))
                    }
                    return (out, back)
                }.value
                guard !Task.isCancelled, library.libraryIdentity == identity else { return }
                outgoing = result.0; incoming = result.1; loading = false
            }
        }
    }
    private func open(_ target: PageLinkTarget) { if navigate(target) { dismiss() } }
}

private struct PageLinkSection: View {
    let title: LocalizedStringKey
    let rows: [LinkDisplayRow]
    let open: (PageLinkTarget) -> Void
    var body: some View {
        Section(title) {
            if rows.isEmpty { Text("Keine Verweise").foregroundStyle(.secondary) }
            ForEach(rows) { row in
                Button { if let target = row.target { open(target) } } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title.isEmpty ? "Seitenverweis" : row.title).lineLimit(2)
                        Text(row.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }.disabled(row.target == nil)
            }
        }
    }
}

private struct ReferenceOption: Identifiable, Sendable {
    let id: UUID
    let title: String
    let headings: [PageHeading]
}

struct PageReferenceSheet: View {
    let pageID: UUID
    let library: WritingLibrary
    let insert: (String, PageLinkTarget) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var options: [ReferenceOption] = []
    @State private var selected: UUID?
    @State private var loading = true
    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView("Seiten werden gelesen …") }
                ForEach(options) { option in
                    DisclosureGroup(isExpanded: Binding(get: { selected == option.id }, set: { selected = $0 ? option.id : nil })) {
                        Button("Ganze Seite verlinken") { choose(option.title, PageLinkTarget(pageID: option.id)) }
                        ForEach(option.headings, id: \.slug) { heading in
                            Button(heading.title.isEmpty ? "Überschrift" : heading.title) { choose(heading.title, PageLinkTarget(pageID: option.id, heading: heading.slug)) }
                        }
                    } label: { Text(option.title.isEmpty ? "Ohne Titel" : option.title) }
                }
                Section { Text("Seitenlinks behalten ihre Identität beim Umbenennen. Überschriftenlinks verwenden den Überschriftentext; beim Ändern dieses Textes kann das Ziel entfallen.").font(.caption).foregroundStyle(.secondary) }
                if let error = library.saveError { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Verweis einfügen")
            .toolbar { Button("Schließen") { dismiss() } }
            .task {
                guard let store = library.store, let source = store.snapshot.pages.first(where: { $0.id == pageID }) else { loading = false; return }
                let pages = store.snapshot.pages, scope = Set(store.snapshot.spaces.map(\.id)), identity = library.libraryIdentity
                let result = await Task.detached(priority: .userInitiated) {
                    let index = PageLinkIndex(libraryID: identity, spaceID: source.spaceID, pages: pages, readableSpaceIDs: scope)
                    return pages.filter { $0.trashedAt == nil }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.map {
                        ReferenceOption(id: $0.id, title: $0.title, headings: index.headings(on: $0.id))
                    }
                }.value
                guard !Task.isCancelled, library.libraryIdentity == identity else { return }
                options = result; loading = false
            }
        }
    }
    private func choose(_ title: String, _ target: PageLinkTarget) { if insert(title, target) { dismiss() } }
}
