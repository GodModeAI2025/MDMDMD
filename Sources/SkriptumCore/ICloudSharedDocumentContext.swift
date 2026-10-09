import Foundation

public enum ICloudSharedDocumentError: Error, Equatable { case invalidRoot, outsideShare, incompleteHierarchy, permissionDenied }
public enum ICloudSharedPermission: Sendable { case readOnly, readWrite, revoked }

/// Canonical owner payloads remain unchanged. Boundary handling is only for
/// validation/navigation, never a revision rewrite or an outbound sync payload.
public struct ICloudSharedDocumentContext: Sendable {
    public let root: ICloudSyncRecordID
    public let canonical: LibrarySnapshot
    public let permission: ICloudSharedPermission
    private let selected: Set<UUID>

    @MainActor public init(root: ICloudSyncRecordID, canonical: LibrarySnapshot,
                           permission: ICloudSharedPermission) throws {
        guard canonical.proposalReceipts?.isEmpty ?? true else { throw ICloudSharedDocumentError.outsideShare }
        var validation = canonical
        let ids = Set(canonical.pages.map(\.id))
        switch root.kind {
        case .page:
            guard canonical.spaces.isEmpty, let page = canonical.pages.first(where: { $0.id == root.id }) else {
                throw ICloudSharedDocumentError.invalidRoot
            }
            for candidate in canonical.pages {
                guard candidate.spaceID == page.spaceID else { throw ICloudSharedDocumentError.outsideShare }
                if candidate.id == page.id { continue }
                var visited: Set<UUID> = [candidate.id], parent = candidate.parentID
                var reachesRoot = false
                while let id = parent {
                    if id == page.id { reachesRoot = true; break }
                    guard visited.insert(id).inserted else { throw LibraryError.hierarchyCycle }
                    guard let ancestor = canonical.pages.first(where: { $0.id == id }) else {
                        throw ICloudSharedDocumentError.incompleteHierarchy
                    }
                    parent = ancestor.parentID
                }
                guard reachesRoot else { throw ICloudSharedDocumentError.outsideShare }
            }
            // An external ancestor is an opaque boundary, not a fetched page.
            // A parent within the selected subtree is still an invalid cycle.
            if let parent = page.parentID, ids.contains(parent) { throw LibraryError.hierarchyCycle }
            validation.spaces = [Space(id: page.spaceID, title: "", createdAt: Date(timeIntervalSince1970: 0))]
            if let index = validation.pages.firstIndex(where: { $0.id == page.id }) { validation.pages[index].parentID = nil }
        case .space:
            guard canonical.spaces.count == 1, canonical.spaces.first?.id == root.id else {
                throw ICloudSharedDocumentError.invalidRoot
            }
            guard canonical.pages.allSatisfy({ $0.spaceID == root.id }) else { throw ICloudSharedDocumentError.outsideShare }
        default: throw ICloudSharedDocumentError.invalidRoot
        }
        guard canonical.revisions.allSatisfy({ ids.contains($0.page.id) }) else { throw ICloudSharedDocumentError.outsideShare }
        try LibraryStore.validate(validation)
        self.root = root; self.canonical = canonical; self.permission = permission; selected = ids
    }
    public func page(_ id: UUID) -> Page? {
        guard permission != .revoked, selected.contains(id) else { return nil }
        return canonical.pages.first { $0.id == id }
    }
    public func visibleParent(of id: UUID) -> UUID? {
        guard let parent = page(id)?.parentID, selected.contains(parent) else { return nil }
        return parent
    }
    public func requireWrite(to id: UUID) throws {
        guard permission == .readWrite, selected.contains(id) else { throw ICloudSharedDocumentError.permissionDenied }
    }
}
