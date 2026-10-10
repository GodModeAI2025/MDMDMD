import Foundation

public enum ICloudShareScope: Sendable { case space(UUID), page(UUID) }
public struct ICloudShareManifest: Equatable, Sendable {
    public let root: ICloudSyncRecordID
    public let pages: Set<UUID>
    public let comments: Set<UUID>
    public let revisions: Set<UUID>
    public let images: Set<UUID>

    @MainActor public init(scope: ICloudShareScope, snapshot: LibrarySnapshot) throws {
        try LibraryStore.validate(snapshot)
        var selected: Set<UUID>
        switch scope {
        case .space(let id):
            guard snapshot.spaces.contains(where: { $0.id == id }) else { throw LibraryError.invalidLibrary }
            root = .init(kind: .space, id: id)
            selected = Set(snapshot.pages.filter { $0.spaceID == id }.map(\.id))
        case .page(let id):
            guard let rootPage = snapshot.pages.first(where: { $0.id == id }) else { throw LibraryError.missingPage }
            root = .init(kind: .page, id: id); selected = [id]
            var changed = true
            while changed {
                let before = selected.count
                for page in snapshot.pages where page.parentID.map(selected.contains) == true {
                    guard page.spaceID == rootPage.spaceID else { throw LibraryError.invalidLibrary }
                    selected.insert(page.id)
                }
                changed = selected.count != before
            }
        }
        for page in snapshot.pages where selected.contains(page.id) {
            if let parent = page.parentID, !selected.contains(parent) {
                guard root.kind == .page && page.id == root.id else { throw LibraryError.invalidLibrary }
            }
        }
        pages = selected
        comments = Set(snapshot.comments.filter { selected.contains($0.pageID) }.map(\.id))
        let history = snapshot.revisions.filter { selected.contains($0.page.id) }
        revisions = Set(history.map(\.id))
        images = Set((snapshot.pages.filter { selected.contains($0.id) } + history.map(\.page))
            .flatMap { ($0.attachments ?? []).map(\.id) })
    }
}
