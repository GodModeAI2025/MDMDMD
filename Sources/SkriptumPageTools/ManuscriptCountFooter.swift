import SwiftUI

struct ManuscriptCountFooter: View {
    let library: WritingLibrary
    let spaceID: UUID?
    @State private var words = 0
    private var key: String { (spaceID?.uuidString ?? "all") + library.pages.map { $0.id.uuidString + $0.revision.uuidString }.joined() }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Manuskript: \(words) Wörter").font(.caption)
            Text("Recherchematerial, Vorlagen und Papierkorb ausgenommen").font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(.bar)
            .task(id: key) {
                let snapshot = library.pages.filter { !$0.trashed && $0.effectivePurpose == .writing && (spaceID == nil || $0.spaceID == spaceID) }.map(\.markdown)
                let result = await Task.detached(priority: .utility) { snapshot.reduce(0) { $0 + $1.split(whereSeparator: { $0.isWhitespace }).count } }.value
                guard !Task.isCancelled else { return }; words = result
            }
    }
}
