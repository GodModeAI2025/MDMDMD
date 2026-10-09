import SwiftUI

/// The callback must persist atomically before returning nil. An error leaves
/// the editor, its undo stacks, and any cell draft untouched.
public struct TableEditingSheet: View {
    private let source: String
    private let apply: (String) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var state: TableEditorState?
    @State private var undo: [TableEditorState] = []
    @State private var redo: [TableEditorState] = []
    @State private var selected: TableCellAddress?
    @State private var draft = ""
    @State private var error: String?
    @State private var removal: TableRemoval?
    @State private var discardPresented = false

    public init(source: String, apply: @escaping (String) -> String?) {
        self.source = source; self.apply = apply
    }
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let state {
                        TableEditorGrid(state: state, selected: selected, choose: choose,
                            removeRow: { requestRemoval(.row($0)) }, removeColumn: { requestRemoval(.column($0)) })
                        if selected != nil {
                            TableCellEditor(draft: $draft, save: saveCell,
                                cancel: { if dirty { discardPresented = true } else { selected = nil } })
                        }
                        TableStructureActions(addRow: addRow, addColumn: addColumn)
                            .disabled(dirty)
                        TableSourcePreview(source: state.source)
                    } else {
                        Text("Diese Tabelle kann nicht strukturiert bearbeitet werden. Der vollständige Quelltext bleibt erhalten.")
                    }
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("table-edit-error") }
                }.padding()
            }
            .navigationTitle("Tabelle bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { if saveCell() { dismiss() } }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Rückgängig", systemImage: "arrow.uturn.backward", action: undoChange)
                        .disabled(undo.isEmpty || dirty).accessibilityIdentifier("table-undo")
                    Button("Wiederholen", systemImage: "arrow.uturn.forward", action: redoChange)
                        .disabled(redo.isEmpty || dirty).accessibilityIdentifier("table-redo")
                    Button("Fertig") { if saveCell() { dismiss() } }
                        .accessibilityIdentifier("table-done")
                }
            }
            .interactiveDismissDisabled(dirty)
            .task {
                guard state == nil else { return }
                do { state = try TableEditorState(source: source) }
                catch { self.error = message(error) }
            }
            .confirmationDialog("Inhalt löschen?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let removal { remove(removal) }; removal = nil
                }
                Button("Abbrechen", role: .cancel) { removal = nil }
            } message: { Text("Die ausgewählte Zeile oder Spalte enthält Text. Sie können das Löschen rückgängig machen.") }
            .confirmationDialog("Zellentext verwerfen?", isPresented: $discardPresented, titleVisibility: .visible) {
                Button("Zellentext verwerfen", role: .destructive) { selected = nil; draft = "" }
                Button("Weiter bearbeiten", role: .cancel) { }
            } message: { Text("Nur der noch nicht übernommene Zellentext wird verworfen. Gespeicherte Tabellenänderungen bleiben erhalten.") }
        }
    }
    private var dirty: Bool {
        guard let state, let selected, let value = state.value(at: selected) else { return false }
        return !draft.utf8.elementsEqual(value.utf8)
    }
    private func choose(_ address: TableCellAddress) {
        guard saveCell(), let value = state?.value(at: address) else { return }
        selected = address; draft = value
    }
    @discardableResult private func saveCell() -> Bool {
        guard dirty, let current = state, let selected,
              let row = current.rows.firstIndex(where: { $0.id == selected.row }),
              let column = current.columns.firstIndex(where: { $0.id == selected.column }) else { return true }
        do {
            let nextSource = try MarkdownTable(current.source).replacingCell(row: row, column: column, markdown: draft)
            return persist(try current.updated(source: nextSource))
        } catch { self.error = message(error); return false }
    }
    @discardableResult private func persist(_ next: TableEditorState) -> Bool {
        guard let current = state else { return false }
        guard !current.source.utf8.elementsEqual(next.source.utf8) else { error = nil; return true }
        if let failure = apply(next.source) { error = failure; return false }
        undo.append(current); trimHistory(); redo = []; state = next; error = nil
        return true
    }
    private func addRow() {
        guard let current = state, !dirty else { return }
        do {
            let table = try MarkdownTable(current.source)
            let value = try table.insertingRow(at: table.bodyRowCount, cells: Array(repeating: "", count: table.columnCount))
            var next = try current.updated(source: value, rows: current.rows + [TableRowIdentity()])
            next.columns = current.columns; _ = persist(next)
        } catch { self.error = message(error) }
    }
    private func addColumn() {
        guard let current = state, !dirty else { return }
        do {
            let table = try MarkdownTable(current.source)
            let value = try table.insertingColumn(at: table.columnCount, heading: "", cells: Array(repeating: "", count: table.bodyRowCount))
            _ = persist(try current.updated(source: value, columns: current.columns + [TableColumnIdentity()]))
        } catch { self.error = message(error) }
    }
    private func requestRemoval(_ target: TableRemoval) {
        guard !dirty, let current = state else { return }
        let populated: Bool
        switch target {
        case .row(let id):
            guard let index = current.rows.firstIndex(where: { $0.id == id }), index > 0 else { return }
            populated = current.cells[index].contains { !$0.isEmpty }
        case .column(let id):
            guard let index = current.columns.firstIndex(where: { $0.id == id }) else { return }
            guard current.columns.count > 1 else { error = message(TableEditingError.lastColumn); return }
            populated = current.cells.contains { !$0[index].isEmpty }
        }
        if populated { removal = target } else { remove(target) }
    }
    private func remove(_ target: TableRemoval) {
        guard let current = state, !dirty else { return }
        do {
            let table = try MarkdownTable(current.source)
            let next: TableEditorState
            switch target {
            case .row(let id):
                guard let index = current.rows.firstIndex(where: { $0.id == id }), index > 0 else { return }
                next = try current.updated(source: table.removingRow(at: index - 1), rows: current.rows.filter { $0.id != id })
            case .column(let id):
                guard let index = current.columns.firstIndex(where: { $0.id == id }) else { return }
                next = try current.updated(source: table.removingColumn(at: index), columns: current.columns.filter { $0.id != id })
            }
            if persist(next) { selected = nil; draft = "" }
        } catch { self.error = message(error) }
    }
    private func undoChange() {
        guard !dirty, let current = state, let previous = undo.last else { return }
        if let failure = apply(previous.source) { error = failure; return }
        undo.removeLast(); redo.append(current); trimHistory(); state = previous; selected = nil; error = nil
    }
    private func redoChange() {
        guard !dirty, let current = state, let next = redo.last else { return }
        if let failure = apply(next.source) { error = failure; return }
        redo.removeLast(); undo.append(current); trimHistory(); state = next; selected = nil; error = nil
    }
    private func trimHistory() {
        if undo.count > 100 { undo.removeFirst(undo.count - 100) }
        if redo.count > 100 { redo.removeFirst(redo.count - 100) }
    }
    private func message(_ error: Error) -> String {
        switch error as? TableEditingError {
        case .lastColumn: String(localized: "Die letzte Spalte kann nicht gelöscht werden.")
        case .invalidCell: String(localized: "Verwenden Sie Inline-Markdown ohne Zeilenumbruch oder Rand-Leerzeichen. Maskieren Sie senkrechte Striche mit einem Rückstrich.")
        default: String(localized: "Die Tabelle konnte nicht bearbeitet werden. Bitte prüfen Sie den Markdown-Quelltext.")
        }
    }
}

private struct TableRowIdentity: Identifiable { let id = UUID() }
private struct TableColumnIdentity: Identifiable { let id = UUID() }
private struct TableCellAddress: Equatable { let row: UUID; let column: UUID }
private enum TableRemoval { case row(UUID), column(UUID) }
private struct TableEditorState {
    let source: String
    let cells: [[String]]
    var rows: [TableRowIdentity]
    var columns: [TableColumnIdentity]
    init(source: String) throws {
        let table = try MarkdownTable(source); self.source = source; cells = table.cells
        rows = cells.map { _ in TableRowIdentity() }; columns = (0..<table.columnCount).map { _ in TableColumnIdentity() }
    }
    func updated(source: String, rows: [TableRowIdentity]? = nil, columns: [TableColumnIdentity]? = nil) throws -> Self {
        var next = try Self(source: source); next.rows = rows ?? self.rows; next.columns = columns ?? self.columns
        return next
    }
    func value(at address: TableCellAddress) -> String? {
        guard let row = rows.firstIndex(where: { $0.id == address.row }), let column = columns.firstIndex(where: { $0.id == address.column }) else { return nil }
        return cells[row][column]
    }
}

private struct TableEditorGrid: View {
    let state: TableEditorState
    let selected: TableCellAddress?
    let choose: (TableCellAddress) -> Void
    let removeRow: (UUID) -> Void
    let removeColumn: (UUID) -> Void
    var body: some View {
        ScrollView(.horizontal) {
            LazyVStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Zeile").frame(width: 80)
                    ForEach(state.columns.enumerated(), id: \.element.id) { number, column in
                        Menu {
                            Button("Spalte löschen", role: .destructive) { removeColumn(column.id) }
                        } label: { Label("Spalte \(number + 1)", systemImage: "ellipsis").frame(minWidth: 150, minHeight: 44) }
                    }
                }
                ForEach(state.rows.enumerated(), id: \.element.id) { number, row in
                    TableGridRow(row: row, rowNumber: number, columns: state.columns, values: state.cells[number], isHeading: number == 0, selected: selected, choose: choose, remove: { removeRow(row.id) })
                }
            }
        }.accessibilityIdentifier("table-cell-grid")
    }
}
private struct TableGridRow: View {
    let row: TableRowIdentity
    let rowNumber: Int
    let columns: [TableColumnIdentity]
    let values: [String]
    let isHeading: Bool
    let selected: TableCellAddress?
    let choose: (TableCellAddress) -> Void
    let remove: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Zeile löschen", role: .destructive, action: remove)
                    .disabled(isHeading)
            } label: { Text(isHeading ? LocalizedStringResource("Kopf") : LocalizedStringResource("Zeile \(rowNumber)")).frame(width: 80, height: 44) }
            ForEach(columns.enumerated(), id: \.element.id) { number, column in
                let address = TableCellAddress(row: row.id, column: column.id)
                Button { choose(address) } label: {
                    Text(cellValue(column.id).isEmpty ? "∅" : cellValue(column.id))
                        .font(.system(.body, design: .monospaced)).lineLimit(3)
                        .frame(width: 150, alignment: .leading).frame(minHeight: 44).padding(8)
                }.buttonStyle(.bordered).tint(selected == address ? .accentColor : .secondary)
                    .accessibilityLabel(Text(isHeading ? LocalizedStringResource("Kopf, Spalte \(number + 1): \(cellValue(column.id))") : LocalizedStringResource("Zeile \(rowNumber), Spalte \(number + 1): \(cellValue(column.id))")))
            }
        }
    }
    private func cellValue(_ columnID: UUID) -> String {
        guard let index = columns.firstIndex(where: { $0.id == columnID }), values.indices.contains(index) else { return "" }
        return values[index]
    }
}
private struct TableCellEditor: View {
    @Binding var draft: String
    let save: () -> Bool
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zelle bearbeiten").font(.headline)
            TextField("Inline-Markdown", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("table-cell-draft")
            HStack {
                Button("Zelle übernehmen") { _ = save() }.buttonStyle(.borderedProminent).accessibilityIdentifier("table-cell-save")
                Button("Abbrechen", action: cancel)
            }
        }
    }
}
private struct TableStructureActions: View {
    let addRow: () -> Void
    let addColumn: () -> Void
    var body: some View {
        HStack {
            Button("Zeile hinzufügen", systemImage: "plus", action: addRow).accessibilityIdentifier("table-add-row")
            Button("Spalte hinzufügen", systemImage: "plus", action: addColumn).accessibilityIdentifier("table-add-column")
        }.buttonStyle(.bordered)
    }
}
private struct TableSourcePreview: View {
    let source: String
    var body: some View {
        DisclosureGroup("Markdown-Quelltext") {
            Text(source).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
