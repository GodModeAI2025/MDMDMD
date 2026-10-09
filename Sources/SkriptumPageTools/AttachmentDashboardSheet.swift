import SwiftUI
#if canImport(SkriptumCore)
import SkriptumCore
#endif

/// A read-only, snapshot-bound inspection of this window's owned library.
struct AttachmentDashboardSheet: View {
    let library: WritingLibrary
    let pageID: UUID?
    let navigate: ((UUID) -> Bool)?
    @Environment(\.dismiss) private var dismiss
    @State private var result: AttachmentDashboardResult?
    @State private var visible: [AttachmentDashboardRow] = []
    @State private var counts = AttachmentDashboardCounts()
    @State private var pageOnly: Bool
    @State private var issuesOnly = false
    @State private var refresh = UUID()
    @State private var loading = false
    @State private var error: String?
    @State private var stale = false

    init(library: WritingLibrary, pageID: UUID? = nil, navigate: ((UUID) -> Bool)? = nil) {
        self.library = library; self.pageID = pageID; self.navigate = navigate
        _pageOnly = State(initialValue: pageID != nil)
    }
    var body: some View {
        NavigationStack {
            List {
                AttachmentDashboardControls(pageOnly: $pageOnly, issuesOnly: $issuesOnly,
                    hasPage: pageID != nil, loading: loading, stale: stale,
                    error: error, refresh: { refresh = UUID() })
                if result != nil {
                    AttachmentDashboardSummary(total: counts.total, active: counts.active,
                        trash: counts.trash, history: counts.history, unused: counts.unused)
                    Section("Anlagen") {
                        if visible.isEmpty { Text("Keine Anlagen für diese Auswahl.").foregroundStyle(.secondary) }
                        ForEach(visible) { row in
                            NavigationLink {
                                AttachmentDashboardDetail(row: row, stale: stale,
                                    open: navigate == nil ? nil : { id in open(id) })
                            } label: { AttachmentDashboardEntryRow(row: row) }
                        }
                    }
                } else if loading {
                    ProgressView("Anlagen werden geprüft …")
                }
            }
            .navigationTitle("Anlagenübersicht")
            .toolbar { Button("Schließen") { dismiss() } }
            .task(id: AttachmentDashboardRequest(libraryID: library.libraryIdentity, refresh: refresh)) { await inspect() }
            .onChange(of: library.libraryIdentity) { _, _ in result = nil; visible = []; counts = AttachmentDashboardCounts(); stale = false }
            .onChange(of: library.pages) { _, _ in invalidateIfChanged() }
            .onChange(of: library.revisions) { _, _ in invalidateIfChanged() }
            .onChange(of: library.spaces) { _, _ in invalidateIfChanged() }
            .onChange(of: pageOnly) { _, _ in updateVisible() }
            .onChange(of: issuesOnly) { _, _ in updateVisible() }
            .onChange(of: pageID) { _, _ in updateVisible() }
        }
    }
    private func inspect() async {
        guard let store = library.store else {
            error = String(localized: "Die Bibliothek ist nicht geöffnet."); return
        }
        let snapshot = store.snapshot, identity = library.libraryIdentity, directory = store.directory
        if result?.libraryID != identity { result = nil; visible = []; counts = AttachmentDashboardCounts() }
        invalidateIfChanged()
        loading = true; error = nil
        do {
            let inventory = try await AttachmentAudit.inspect(libraryID: identity, snapshot: snapshot, mediaRoot: directory)
            try Task.checkCancellation()
            guard library.libraryIdentity == identity, library.store === store,
                  store.snapshot == snapshot else {
                stale = true; loading = false
                error = String(localized: "Die Bibliothek hat sich während der Prüfung geändert. Bitte erneut prüfen.")
                return
            }
            let worker = Task.detached(priority: .utility) {
                try AttachmentDashboardResult(inventory: inventory, snapshot: snapshot)
            }
            let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            guard library.libraryIdentity == identity, library.store === store, store.snapshot == snapshot else {
                stale = true; loading = false; return
            }
            result = prepared
            stale = false; loading = false; updateVisible()
        } catch is CancellationError {
            // The replacement task owns loading/error state.
        } catch {
            guard !Task.isCancelled else { return }
            loading = false
            self.error = String(localized: "Die Anlagenprüfung konnte nicht abgeschlossen werden: \(error.localizedDescription)")
        }
    }
    private func invalidateIfChanged() {
        guard let result else { return }
        stale = library.libraryIdentity != result.libraryID || library.store?.snapshot != result.snapshot
    }
    private func updateVisible() {
        // References, including history, may belong to a page with no descriptor.
        visible = (result?.rows ?? []).filter { row in
            let matchesPage = pageID.map { id in row.ownerPageIDs.contains(id) || row.references.contains { $0.pageID == id } } ?? true
            return (!pageOnly || matchesPage) && (!issuesOnly || row.hasIssue)
        }
        counts = AttachmentDashboardCounts(rows: visible)
    }
    private func open(_ id: UUID) {
        guard let result, !stale, result.libraryID == library.libraryIdentity, library.store?.snapshot == result.snapshot,
              let current = library.store?.snapshot.pages.first(where: { $0.id == id }), current.trashedAt == nil else {
            stale = true; error = String(localized: "Der Verweis ist nicht mehr aktuell. Bitte erneut prüfen."); return
        }
        if navigate?(id) == true { dismiss() }
        else { error = library.saveError ?? String(localized: "Die Seite konnte nicht geöffnet werden.") }
    }
}
private struct AttachmentDashboardRequest: Equatable { let libraryID: UUID; let refresh: UUID }
nonisolated private struct AttachmentReferenceGroup: Identifiable, Sendable {
    struct ID: Hashable, Sendable { let pageID: UUID; let revisionID: UUID; let context: String }
    let id: ID
    let pageID: UUID
    let revisionID: UUID
    let title: String
    let context: AttachmentReferenceContext
    let count: Int
    let missingMetadata: Bool
}
nonisolated private struct AttachmentDashboardRow: Identifiable, Sendable {
    let id: UUID
    let name: String
    let metadata: MediaAttachment?
    let status: AttachmentStorageStatus
    let references: [AttachmentReferenceGroup]
    let ownerPageIDs: Set<UUID>
    let active: Int
    let trash: Int
    let history: Int
    let unused: Bool
    let hasIssue: Bool
}
nonisolated private struct AttachmentDashboardResult: Sendable {
    let libraryID: UUID
    let snapshot: LibrarySnapshot
    let rows: [AttachmentDashboardRow]
    init(inventory: AttachmentInventory, snapshot: LibrarySnapshot) throws {
        self.snapshot = snapshot; libraryID = inventory.libraryID
        let names = Dictionary(uniqueKeysWithValues: snapshot.pages.map { ($0.id, $0.title) })
        rows = try inventory.entries.map { entry in
            try Task.checkCancellation()
            let grouped: [AttachmentReferenceGroup.ID: [AttachmentReference]] = Dictionary(grouping: entry.references) { reference in
                AttachmentReferenceGroup.ID(pageID: reference.pageID, revisionID: reference.revisionID, context: reference.context.key)
            }
            var groups: [AttachmentReferenceGroup] = []
            for (id, references) in grouped {
                try Task.checkCancellation()
                guard let first = references.first else { continue }
                let oldTitle = first.context == .revision
                    ? snapshot.revisions.first(where: { $0.page.id == id.pageID && $0.page.revision == id.revisionID })?.page.title : nil
                let title = oldTitle ?? names[id.pageID] ?? String(localized: "Frühere Seite")
                groups.append(AttachmentReferenceGroup(id: id, pageID: id.pageID, revisionID: id.revisionID,
                    title: title, context: first.context, count: references.count,
                    missingMetadata: references.contains { !$0.hasPageMetadata }))
            }
            groups.sort { lhs, rhs in
                if lhs.context.key != rhs.context.key { return lhs.context.key < rhs.context.key }
                if lhs.title != rhs.title { return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending }
                return lhs.revisionID.uuidString < rhs.revisionID.uuidString
            }
            return AttachmentDashboardRow(id: entry.id,
                name: entry.metadata?.filename ?? String(localized: "Anlage ohne Metadaten"),
                metadata: entry.metadata, status: entry.storageStatus, references: groups,
                ownerPageIDs: entry.currentMetadataPageIDs.union(entry.retainedMetadataPageIDs),
                active: entry.activeReferenceCount, trash: entry.trashedReferenceCount,
                history: entry.historicalReferenceCount, unused: entry.isUnusedInCurrentPages,
                hasIssue: entry.storageStatus != .verified || groups.contains { $0.missingMetadata })
        }

    }
}
nonisolated private struct AttachmentDashboardCounts {
    var total = 0; var active = 0; var trash = 0; var history = 0; var unused = 0
    init(rows: [AttachmentDashboardRow] = []) {
        total = rows.count
        for row in rows { active += row.active; trash += row.trash; history += row.history; unused += row.unused ? 1 : 0 }
    }
}
private struct AttachmentDashboardControls: View {
    @Binding var pageOnly: Bool
    @Binding var issuesOnly: Bool
    let hasPage: Bool
    let loading: Bool
    let stale: Bool
    let error: String?
    let refresh: () -> Void
    var body: some View {
        Section {
            if hasPage {
                Picker("Bereich", selection: $pageOnly) {
                    Text("Diese Seite").tag(true)
                    Text("Bibliothek").tag(false)
                }.pickerStyle(.segmented)
            }
            Toggle("Nur Auffälligkeiten", isOn: $issuesOnly)
            Button("Erneut prüfen", systemImage: "arrow.clockwise", action: refresh)
                .accessibilityIdentifier("attachment-refresh")
            if loading { ProgressView("Prüfung läuft …") }
            if stale { AttachmentWarningLabel("Ergebnis veraltet", symbol: "clock.badge.exclamationmark") }
            if let error { Text(error).foregroundStyle(.red) }
            Text("Dateien und Metadaten werden nur gelesen. Nicht in aktuellen Seiten verwendet bedeutet nicht, dass eine Anlage gelöscht werden kann.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
private struct AttachmentDashboardSummary: View {
    let total: Int; let active: Int; let trash: Int; let history: Int; let unused: Int
    @State private var expanded = false
    var body: some View {
        Section("Ausgewählte Anlagen") {
            LabeledContent("Anlagen", value: total.formatted())
            DisclosureGroup("Verwendung und Verlauf", isExpanded: $expanded) {
                LabeledContent("Verweise in aktiven Seiten", value: active.formatted())
                LabeledContent("Verweise im Papierkorb", value: trash.formatted())
                LabeledContent("Verweise im Verlauf", value: history.formatted())
                LabeledContent("Ohne aktive Verwendung", value: unused.formatted())
                Text("Verweiszahlen umfassen alle Seiten dieser Bibliothek für die ausgewählten Anlagen.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
private struct AttachmentDashboardEntryRow: View {
    let row: AttachmentDashboardRow
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.name).font(.headline)
            AttachmentStatusLabel(status: row.status)
            if let metadata = row.metadata {
                HStack {
                    Text(metadata.mediaType)
                    Text(Int64(metadata.byteCount), format: .byteCount(style: .file))
                }.font(.caption).foregroundStyle(.secondary)
            }
            Text("Aktiv: \(row.active) · Papierkorb: \(row.trash) · Verlauf: \(row.history)").font(.caption)
            if row.references.contains(where: \.missingMetadata) {
                AttachmentWarningLabel("Metadaten fehlen auf einer verweisenden Seite").font(.caption)
            }
        }.padding(.vertical, 4)
    }
}
private struct AttachmentStatusLabel: View {
    let status: AttachmentStorageStatus
    var body: some View {
        Label {
            Text(status.title).foregroundStyle(Color.primary)
        } icon: {
            Image(systemName: status == .verified ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(status == .verified ? Color.secondary : Color.orange)
        }.font(.caption)
    }
}
private struct AttachmentDashboardDetail: View {
    let row: AttachmentDashboardRow
    let stale: Bool
    let open: ((UUID) -> Void)?
    var body: some View {
        List {
            Section("Datei") {
                Text(row.name)
                AttachmentStatusLabel(status: row.status)
                if let metadata = row.metadata {
                    LabeledContent("Medientyp", value: metadata.mediaType)
                    LabeledContent("Größe") { Text(Int64(metadata.byteCount), format: .byteCount(style: .file)) }
                }
                if row.unused { Text("Keine Verweise in aktiven Seiten. Papierkorb und Verlauf können diese Anlage weiterhin benötigen.").font(.caption) }
                if stale { Text("Ergebnis veraltet. Die Übersicht muss erneut geprüft werden.").foregroundStyle(Color.primary) }
            }
            AttachmentReferencesSection(title: "Aktive Seiten", references: row.references.filter { $0.context == .activePage }, canOpen: !stale, open: open)
            AttachmentReferencesSection(title: "Papierkorb", references: row.references.filter { $0.context == .trashedPage }, canOpen: false, open: nil)
            AttachmentReferencesSection(title: "Verlauf", references: row.references.filter { $0.context == .revision }, canOpen: false, open: nil)
        }.navigationTitle("Anlagendetails")
    }
}
private struct AttachmentReferencesSection: View {
    let title: LocalizedStringKey
    let references: [AttachmentReferenceGroup]
    let canOpen: Bool
    let open: ((UUID) -> Void)?
    var body: some View {
        Section(title) {
            if references.isEmpty { Text("Keine Verweise").foregroundStyle(.secondary) }
            ForEach(references) { reference in
                AttachmentReferenceRow(reference: reference, canOpen: canOpen, open: open)
            }
        }
    }
}
private struct AttachmentReferenceRow: View {
    let reference: AttachmentReferenceGroup
    let canOpen: Bool
    let open: ((UUID) -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(reference.title)
            Text("\(reference.count) Verweise").font(.caption).foregroundStyle(.secondary)
            if reference.context == .revision {
                Text("Revision \(reference.revisionID.uuidString)").font(.caption2).textSelection(.enabled)
            }
            if reference.missingMetadata {
                AttachmentWarningLabel("Metadaten fehlen auf dieser Seite").font(.caption)
            }
            if canOpen, !reference.missingMetadata, let open {
                Button("Seite öffnen", systemImage: "doc.text") { open(reference.pageID) }
            }
        }
    }
}
private struct AttachmentWarningLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    init(_ title: LocalizedStringKey, symbol: String = "exclamationmark.triangle") {
        self.title = title; self.symbol = symbol
    }
    var body: some View {
        Label { Text(title).foregroundStyle(Color.primary) } icon: {
            Image(systemName: symbol).foregroundStyle(Color.orange)
        }
    }
}
private extension AttachmentReferenceContext {
    nonisolated var key: String { switch self { case .activePage: "active"; case .trashedPage: "trash"; case .revision: "history" } }
}
private extension AttachmentStorageStatus {
    var title: LocalizedStringResource {
        switch self {
        case .notChecked: "Noch nicht geprüft"
        case .verified: "Datei geprüft"
        case .missingMetadata: "Metadaten fehlen"
        case .missingFile: "Datei fehlt"
        case .invalidFile: "Datei ungültig"
        case .unavailableFile: "Datei nicht prüfbar"
        case .conflictingMetadata: "Widersprüchliche Metadaten"
        }
    }
}
