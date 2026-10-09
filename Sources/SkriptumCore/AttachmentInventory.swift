import Foundation
import Markdown

public enum AttachmentStorageStatus: Equatable, Sendable {
    case notChecked, verified, missingMetadata, missingFile, invalidFile, conflictingMetadata
}
public enum AttachmentReferenceContext: Equatable, Sendable { case activePage, trashedPage, revision }
public struct AttachmentReference: Equatable, Sendable {
    public let attachmentID: UUID
    public let pageID: UUID
    public let revisionID: UUID
    public let context: AttachmentReferenceContext
    public let label: String
    public let hasPageMetadata: Bool
}
public struct AttachmentInventoryEntry: Identifiable, Sendable {
    public let id: UUID
    public let metadata: MediaAttachment?
    public let storageStatus: AttachmentStorageStatus
    public let references: [AttachmentReference]
    public let currentMetadataPageIDs: Set<UUID>
    public let retainedMetadataPageIDs: Set<UUID>
    public var activeReferenceCount: Int { references.filter { $0.context == .activePage }.count }
    public var trashedReferenceCount: Int { references.filter { $0.context == .trashedPage }.count }
    public var historicalReferenceCount: Int { references.filter { $0.context == .revision }.count }
    public var isUnusedInCurrentPages: Bool { activeReferenceCount == 0 }
    public var isRetainedByHistoryOrTrash: Bool { !retainedMetadataPageIDs.isEmpty || trashedReferenceCount > 0 || historicalReferenceCount > 0 }
}

/// Read-only inventory of an explicitly supplied owned-library snapshot.
/// It never enumerates paths, reads media, heals metadata or removes files.
/// Probe must use LibraryStore.attachmentData/MediaValidation and return honest
/// storage states; default is notChecked. Conflicting/missing metadata is never probed.
public struct AttachmentInventory: Sendable {
    public let libraryID: UUID
    public let entries: [AttachmentInventoryEntry]
    public init(libraryID: UUID, snapshot: LibrarySnapshot, probe: ((MediaAttachment) -> AttachmentStorageStatus)? = nil) {
        // The only throwing operation in the shared builder is the supplied
        // cancellation check; this synchronous initializer supplies a no-op.
        self.libraryID = libraryID
        self.entries = try! Self.build(snapshot: snapshot, probe: probe, check: {})
    }
    init(libraryID: UUID, snapshot: LibrarySnapshot, checkingCancellation: Bool) throws {
        self.libraryID = libraryID
        self.entries = try Self.build(snapshot: snapshot, probe: nil, check: { if checkingCancellation { try Task.checkCancellation() } })
    }
    private init(libraryID: UUID, entries: [AttachmentInventoryEntry]) { self.libraryID = libraryID; self.entries = entries }
    func applyingStatuses(_ statuses: [UUID: AttachmentStorageStatus]) -> Self {
        Self(libraryID: libraryID, entries: entries.map { entry in
            .init(id: entry.id, metadata: entry.metadata, storageStatus: statuses[entry.id] ?? entry.storageStatus,
                  references: entry.references, currentMetadataPageIDs: entry.currentMetadataPageIDs, retainedMetadataPageIDs: entry.retainedMetadataPageIDs)
        })
    }
    private static func build(snapshot: LibrarySnapshot, probe: ((MediaAttachment) -> AttachmentStorageStatus)?, check: () throws -> Void) throws -> [AttachmentInventoryEntry] {
        try check()
        var metadata: [UUID: MediaAttachment] = [:], conflicts = Set<UUID>()
        var currentOwners: [UUID: Set<UUID>] = [:], retainedOwners: [UUID: Set<UUID>] = [:]
        var references: [UUID: [AttachmentReference]] = [:]
        func consume(_ page: Page, context: AttachmentReferenceContext) throws {
            try check()
            for item in page.attachments ?? [] {
                try check()
                if let existing = metadata[item.id], !Self.exactDescriptor(existing, item) { conflicts.insert(item.id) }
                else { metadata[item.id] = item }
                if context == .activePage { currentOwners[item.id, default: []].insert(page.id) }
                else { retainedOwners[item.id, default: []].insert(page.id) }
            }
            try check()
            let document = Document(parsing: page.markdown)
            try check()
            var pending: [any Markup] = [document]
            while let node = pending.popLast() {
                try check()
                if node is CodeBlock || node is InlineCode || node is HTMLBlock || node is InlineHTML { continue }
                let destination: String?, label: String
                if let image = node as? Image { destination = image.source; label = image.plainText }
                else if let link = node as? Link { destination = link.destination; label = link.plainText }
                else { destination = nil; label = "" }
                if let destination, let id = Self.mediaID(destination) {
                    references[id, default: []].append(.init(attachmentID:id,pageID:page.id,revisionID:page.revision,context:context,label:label,hasPageMetadata:(page.attachments ?? []).contains { $0.id == id }))
                }
                if !(node is Image) { pending.append(contentsOf: Array(node.children).reversed()) }
            }

        }
        for page in snapshot.pages { try consume(page, context: page.trashedAt == nil ? .activePage : .trashedPage) }
        for revision in snapshot.revisions { try consume(revision.page, context: .revision) }
        let ids = Set(metadata.keys).union(references.keys)
        return try ids.sorted { $0.uuidString < $1.uuidString }.map { id in
            try check()
            let item = metadata[id]
            let status: AttachmentStorageStatus
            if conflicts.contains(id) { status = .conflictingMetadata }
            else if let item { status = probe?(item) ?? .notChecked }
            else { status = .missingMetadata }
            return .init(id:id,metadata:item,storageStatus:status,references:references[id] ?? [],currentMetadataPageIDs:currentOwners[id] ?? [],retainedMetadataPageIDs:retainedOwners[id] ?? [])
        }
    }
    /// References in the current page (including trash), excluding historical revisions.
    public func references(on pageID: UUID) -> [AttachmentReference] {
        entries.flatMap(\.references).filter { $0.pageID == pageID && $0.context != .revision }
    }
    private static func exactDescriptor(_ left: MediaAttachment, _ right: MediaAttachment) -> Bool {
        left.id == right.id && left.byteCount == right.byteCount
            && left.filename.utf8.elementsEqual(right.filename.utf8)
            && left.mediaType.utf8.elementsEqual(right.mediaType.utf8)
            && left.sha256.utf8.elementsEqual(right.sha256.utf8)
    }
    private static func mediaID(_ destination: String) -> UUID? {
        guard destination.hasPrefix("media/"), destination.utf8.count == 42 else { return nil }
        return UUID(uuidString:String(destination.dropFirst(6)))
    }
}
