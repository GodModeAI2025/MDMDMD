import Foundation
import CryptoKit
import Darwin

public enum ICloudSharedStoreError: Error, Equatable { case invalidIdentity, invalidCheckpoint, unsafeFile, persistence, capacity, staleCheckpoint, pendingLocalChanges }
public struct ICloudSharedStoreIdentity: Codable, Hashable, Sendable {
    public let accountID: String
    public let ownerID: String
    public let zoneName: String
    public let shareName: String
    public let root: ICloudSyncRecordID
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.root == rhs.root && lhs.accountID.utf8.elementsEqual(rhs.accountID.utf8) &&
        lhs.ownerID.utf8.elementsEqual(rhs.ownerID.utf8) && lhs.zoneName.utf8.elementsEqual(rhs.zoneName.utf8) &&
        lhs.shareName.utf8.elementsEqual(rhs.shareName.utf8)
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(root)
        for value in [accountID, ownerID, zoneName, shareName] { hasher.combine(value.utf8.count); for byte in value.utf8 { hasher.combine(byte) } }
    }
    public init(accountID: String, ownerID: String, zoneName: String, shareName: String, root: ICloudSyncRecordID) throws {
        guard [.page, .space].contains(root.kind), [accountID, ownerID, zoneName, shareName].allSatisfy({
            !$0.isEmpty && $0.utf8.count <= 256 && $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
        }) else { throw ICloudSharedStoreError.invalidIdentity }
        self.accountID = accountID; self.ownerID = ownerID; self.zoneName = zoneName; self.shareName = shareName; self.root = root
    }
}

/// Separate share/account checkpoint; access grants are never persisted. Calls
/// serialize on MainActor. App extensions need a cross-process locking contract.
@MainActor public final class ICloudSharedDocumentStore {
    private static let maximumBytes = 64 * 1024 * 1024
    private let descriptor: Int32
    private let filename: String
    public let identity: ICloudSharedStoreIdentity
    public let fileURL: URL
    private struct Checkpoint: Codable {
        var schemaVersion = 1
        let identity: ICloudSharedStoreIdentity
        let revision: UUID
        let canonical: LibrarySnapshot
        var pending: [ICloudSyncChange]?
    }
    public init(directory: URL, identity: ICloudSharedStoreIdentity) throws {
        _ = try ICloudSharedStoreIdentity(accountID: identity.accountID, ownerID: identity.ownerID, zoneName: identity.zoneName, shareName: identity.shareName, root: identity.root)
        self.identity = identity
        let digest = SHA256.hash(data: try Self.encode(identity)).map { String(format: "%02x", $0) }.joined()
        filename = "icloud-shared-" + digest + ".json"
        fileURL = directory.appendingPathComponent(filename)
        descriptor = try Self.openDirectory(directory)
    }
    deinit { Darwin.close(descriptor) }
    public func checkpointRevision() throws -> UUID? { try load()?.revision }
    /// Offline/restored documents default to no grant. The runtime must obtain
    /// the current CKShare permission before requesting an accessible context.
    public func context(permission: ICloudSharedPermission = .revoked) throws -> ICloudSharedDocumentContext? {
        guard let checkpoint = try load() else { return nil }
        return try ICloudSharedDocumentContext(root: identity.root, canonical: checkpoint.canonical, permission: permission)
    }
    @discardableResult public func replace(_ canonical: LibrarySnapshot, expectedRevision: UUID?) throws -> UUID {
        _ = try ICloudSharedDocumentContext(root: identity.root, canonical: canonical, permission: .revoked)
        let old = try load()
        guard old?.revision == expectedRevision else { throw ICloudSharedStoreError.staleCheckpoint }
        guard old?.pending?.isEmpty ?? true else { throw ICloudSharedStoreError.pendingLocalChanges }
        if let old, try Self.encode(old.canonical) == Self.encode(canonical) { return old.revision }
        let next = Checkpoint(identity: identity, revision: UUID(), canonical: canonical)
        try persist(next)
        return next.revision
    }
    public func pendingChanges() throws -> [ICloudSyncChange] { try load()?.pending ?? [] }
    /// The runtime supplies a fresh native participant grant. Local text and its
    /// immutable outgoing chain are persisted in one atomic checkpoint.
    @discardableResult public func editMarkdown(pageID: UUID, expectedPageRevision: UUID,
                                               markdown: String, permission: ICloudSharedPermission) throws -> UUID {
        guard let checkpoint = try load() else { throw ICloudSharedStoreError.invalidCheckpoint }
        let context = try ICloudSharedDocumentContext(root: identity.root, canonical: checkpoint.canonical, permission: permission)
        try context.requireWrite(to: pageID)
        var canonical = checkpoint.canonical
        guard let index = canonical.pages.firstIndex(where: { $0.id == pageID }),
              canonical.pages[index].revision == expectedPageRevision else { throw ICloudSharedStoreError.staleCheckpoint }
        let original = canonical.pages[index]
        if original.markdown.utf8.elementsEqual(markdown.utf8) { return original.revision }
        var pending = checkpoint.pending ?? []
        if !canonical.revisions.contains(where: { $0.id == original.revision }) {
            let history = Revision(page: original, author: identity.accountID, capturedAt: Date())
            canonical.revisions.append(history)
            let payload = try ICloudMetadataPayload(value: history, baseDigest: nil)
            pending.append(ICloudSyncChange(recordID: .init(kind: .revision, id: history.id),
                revisionID: try payload.revisionID(), operation: .upsert, payload: try payload.encoded()))
        }
        canonical.pages[index].blocks = MarkdownReconciler.reconcile(markdown, previous: original.blocks)
        canonical.pages[index].revision = UUID(); canonical.pages[index].modifiedAt = Date()
        let edited = canonical.pages[index]
        let payload = try ICloudPagePayload(page: edited, baseRevision: original.revision).encoded()
        guard payload.count <= 8 * 1024 * 1024, pending.count < 4096 else { throw ICloudSharedStoreError.capacity }
        pending.append(ICloudSyncChange(recordID: .init(kind: .page, id: pageID), revisionID: edited.revision, operation: .upsert, payload: payload))
        _ = try ICloudSharedDocumentContext(root: identity.root, canonical: canonical, permission: permission)
        try persist(Checkpoint(identity: identity, revision: UUID(), canonical: canonical, pending: pending))
        return edited.revision
    }
    /// Each record's queue is ordered. A later response cannot skip an ancestor.
    @discardableResult public func acknowledge(recordID: ICloudSyncRecordID, revisionID: UUID) throws -> Bool {
        guard let checkpoint = try load() else { return false }
        var pending = checkpoint.pending ?? []
        guard let index = pending.firstIndex(where: { $0.recordID == recordID }),
              pending[index].revisionID == revisionID else { return false }
        pending.remove(at: index)
        try persist(Checkpoint(identity: identity, revision: UUID(), canonical: checkpoint.canonical, pending: pending))
        return true
    }
    @discardableResult public func addComment(pageID: UUID, blockID: UUID? = nil, quotedText: String = "",
                                             body: String, permission: ICloudSharedPermission) throws -> Comment {
        guard let checkpoint = try load(), !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let page = checkpoint.canonical.pages.first(where: { $0.id == pageID }),
              blockID.map({ id in page.blocks.contains { $0.id == id } }) ?? true else { throw ICloudSharedStoreError.invalidCheckpoint }
        let comment = Comment(pageID: pageID, blockID: blockID, quotedText: quotedText, body: body, author: identity.accountID)
        try commitComment(comment, previous: nil, checkpoint: checkpoint, permission: permission)
        return comment
    }
    @discardableResult public func replyToComment(_ id: UUID, body: String, permission: ICloudSharedPermission) throws -> Comment {
        guard let checkpoint = try load(), !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let selected = checkpoint.canonical.comments.first(where: { $0.id == id }),
              let root = checkpoint.canonical.comments.first(where: { $0.id == (selected.parentCommentID ?? selected.id) && $0.parentCommentID == nil }) else {
            throw ICloudSharedStoreError.invalidCheckpoint
        }
        let page = checkpoint.canonical.pages.first { $0.id == root.pageID }
        let blockID = root.blockID.flatMap { id in page?.blocks.contains(where: { $0.id == id }) == true ? id : nil }
        var reply = Comment(pageID: root.pageID, blockID: blockID, quotedText: root.quotedText, body: body, author: identity.accountID)
        reply.parentCommentID = root.id
        try commitComment(reply, previous: nil, checkpoint: checkpoint, permission: permission)
        return reply
    }
    public func setCommentResolved(_ id: UUID, resolved: Bool, permission: ICloudSharedPermission) throws {
        guard let checkpoint = try load(), let selected = checkpoint.canonical.comments.first(where: { $0.id == id }),
              let root = checkpoint.canonical.comments.first(where: { $0.id == (selected.parentCommentID ?? selected.id) && $0.parentCommentID == nil }) else {
            throw ICloudSharedStoreError.invalidCheckpoint
        }
        var updated = root; updated.resolvedAt = resolved ? (root.resolvedAt ?? Date()) : nil
        try commitComment(updated, previous: root, checkpoint: checkpoint, permission: permission)
    }
    private func commitComment(_ comment: Comment, previous: Comment?, checkpoint: Checkpoint, permission: ICloudSharedPermission) throws {
        let context = try ICloudSharedDocumentContext(root: identity.root, canonical: checkpoint.canonical, permission: permission)
        try context.requireWrite(to: comment.pageID)
        if let previous, try Self.encode(previous) == Self.encode(comment) { return }
        var canonical = checkpoint.canonical
        if let index = canonical.comments.firstIndex(where: { $0.id == comment.id }) { canonical.comments[index] = comment }
        else { canonical.comments.append(comment) }
        _ = try ICloudSharedDocumentContext(root: identity.root, canonical: canonical, permission: permission)
        let base = try previous.map { try ICloudMetadataPayload<Comment>.digest(of: $0) }
        let payload = try ICloudMetadataPayload(value: comment, baseDigest: base)
        var pending = checkpoint.pending ?? []
        pending.append(ICloudSyncChange(recordID: .init(kind: .comment, id: comment.id), revisionID: try payload.revisionID(), operation: .upsert, payload: try payload.encoded()))
        try persist(Checkpoint(identity: identity, revision: UUID(), canonical: canonical, pending: pending))
    }
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    private func load() throws -> Checkpoint? {
        let fd = Darwin.openat(descriptor, filename, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0, errno == ENOENT { return nil }
        guard fd >= 0 else { throw ICloudSharedStoreError.unsafeFile }
        defer { Darwin.close(fd) }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_nlink == 1, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw ICloudSharedStoreError.unsafeFile }
        guard info.st_size > 0, info.st_size <= Self.maximumBytes else { throw ICloudSharedStoreError.capacity }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0, count <= Self.maximumBytes - bytes.count else { throw ICloudSharedStoreError.persistence }
            if count == 0 { break }; bytes.append(contentsOf: buffer.prefix(count))
        }
        let value = try JSONDecoder().decode(Checkpoint.self, from: bytes)
        guard value.schemaVersion == 1, try Self.encode(value.identity) == Self.encode(identity) else { throw ICloudSharedStoreError.invalidCheckpoint }
        _ = try ICloudSharedDocumentContext(root: identity.root, canonical: value.canonical, permission: .revoked)
        let pending = value.pending ?? []
        guard pending.count <= 4096 else { throw ICloudSharedStoreError.capacity }
        for change in pending {
            guard change.operation == .upsert, change.payload.count <= 8 * 1024 * 1024 else { throw ICloudSharedStoreError.invalidCheckpoint }
            switch change.recordID.kind {
            case .page:
                let payload = try ICloudPagePayload.decode(change.payload, expectedPageID: change.recordID.id, expectedRevision: change.revisionID)
                guard value.canonical.pages.contains(where: { $0.id == payload.page.id }), try payload.encoded() == change.payload else { throw ICloudSharedStoreError.invalidCheckpoint }
            case .comment:
                let payload = try ICloudMetadataPayload<Comment>.decode(change.payload)
                guard payload.value.id == change.recordID.id, try payload.revisionID() == change.revisionID,
                      value.canonical.pages.contains(where: { $0.id == payload.value.pageID }) else { throw ICloudSharedStoreError.invalidCheckpoint }
            case .revision:
                let payload = try ICloudMetadataPayload<Revision>.decode(change.payload)
                guard payload.value.id == change.recordID.id, try payload.revisionID() == change.revisionID,
                      value.canonical.pages.contains(where: { $0.id == payload.value.page.id }) else { throw ICloudSharedStoreError.invalidCheckpoint }
            default: throw ICloudSharedStoreError.invalidCheckpoint
            }
        }
        return value
    }
    private func persist(_ checkpoint: Checkpoint) throws {
        let pending = checkpoint.pending ?? []
        guard pending.count <= 4096, pending.allSatisfy({ $0.payload.count <= 8 * 1024 * 1024 }) else { throw ICloudSharedStoreError.capacity }
        let bytes = try Self.encode(checkpoint)
        guard bytes.count <= Self.maximumBytes else { throw ICloudSharedStoreError.capacity }
        let temporary = ".icloud-shared-" + UUID().uuidString
        let fd = Darwin.openat(descriptor, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ICloudSharedStoreError.persistence }
        defer { Darwin.close(fd); Darwin.unlinkat(descriptor, temporary, 0) }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw ICloudSharedStoreError.persistence }; offset += count
            }
        }
        guard Darwin.fsync(fd) == 0, Darwin.renameat(descriptor, temporary, descriptor, filename) == 0,
              Darwin.fsync(descriptor) == 0 else { throw ICloudSharedStoreError.persistence }
    }

    static func openDirectory(_ directory: URL) throws -> Int32 {
        guard directory.isFileURL, directory.path.hasPrefix("/") else { throw ICloudSharedStoreError.unsafeFile }
        let components = directory.path.split(separator: "/").map(String.init)
        guard !components.isEmpty, components.allSatisfy({ $0 != "." && $0 != ".." }) else { throw ICloudSharedStoreError.unsafeFile }
        var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw ICloudSharedStoreError.persistence }
        for component in components {
            var next = Darwin.openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0, errno == ENOENT {
                if Darwin.mkdirat(fd, component, 0o700) != 0, errno != EEXIST { Darwin.close(fd); throw ICloudSharedStoreError.persistence }
                next = Darwin.openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            Darwin.close(fd)
            guard next >= 0 else { throw ICloudSharedStoreError.unsafeFile }; fd = next
        }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0, info.st_uid == getuid() else { Darwin.close(fd); throw ICloudSharedStoreError.unsafeFile }
        return fd
    }
}
