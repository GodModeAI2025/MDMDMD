import Foundation
import CryptoKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif

enum ICloudPageConflictError: Error { case unavailable, stale, invalidDraft }

struct ICloudPageConflict: Identifiable, Sendable {
    let scope: ICloudSyncScope
    let local: Page
    let remote: Page
    let change: ICloudSyncChange
    private let localDigest: String
    var id: UUID { local.id }
    var reviewIdentity: ICloudConflictReviewIdentity {
        .init(scope: scope, pageID: id, localRevision: local.revision, remoteRevision: remote.revision,
            localDigest: localDigest, remoteDigest: Self.digest(change.payload))
    }
    init(scope: ICloudSyncScope, local: Page, change: ICloudSyncChange) throws {
        guard change.recordID == ICloudSyncRecordID(kind: .page, id: local.id), change.operation == .upsert else { throw ICloudPageConflictError.stale }
        remote = try ICloudPagePayload.decode(change.payload, expectedPageID: local.id, expectedRevision: change.revisionID).page
        guard remote.revision != local.revision else { throw ICloudPageConflictError.stale }
        self.scope = scope; self.local = local; self.change = change
        localDigest = Self.digest(try ICloudMetadataPayload<Page>.valueBytes(local))
    }
    static func admitCompletion(scope: ICloudSyncScope, expectedScope: ICloudSyncScope, expected: ICloudSyncChange, latest: ICloudSyncChange?,
        queued: ICloudSyncChange?, resolvedRevision: UUID) throws {
        guard scope == expectedScope,
              expected.recordID.kind == .page, expected.operation == .upsert,
              resolvedRevision != expected.revisionID,
              let latest, latest == expected,
              let queued, queued.recordID == expected.recordID, queued.operation == .upsert,
              queued.revisionID == resolvedRevision,
              try ICloudPagePayload.decode(queued.payload, expectedPageID: expected.recordID.id,
                expectedRevision: resolvedRevision).baseRevision == expected.revisionID else { throw ICloudPageConflictError.stale }
    }
    static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
}
struct ICloudConflictReviewIdentity: Codable, Equatable, Sendable {
    let scope: ICloudSyncScope
    let pageID: UUID, localRevision: UUID, remoteRevision: UUID
    let localDigest: String, remoteDigest: String
}
/// Private per-window buffers. The page-scoped catalog can recover older
/// comparisons explicitly; each write preserves other windows and comparisons.
@MainActor final class ICloudConflictReviewStore {
    struct Summary: Identifiable {
        let id: String, draftID: UUID, identity: ICloudConflictReviewIdentity
        let updatedAt: Date, preview: String
        let matchesCurrentComparison: Bool
    }
    struct Listing { let drafts: [Summary]; let unreadableCount: Int }
    private struct Draft: Codable {
        var schemaVersion = 1
        let identity: ICloudConflictReviewIdentity, id: UUID, text: String, updatedAt: Date
    }
    private struct PageScope: Codable { let scope: ICloudSyncScope; let pageID: UUID }
    let draftID: UUID
    private let identity: ICloudConflictReviewIdentity
    private let pagePrefix: String
    private let files: ICloudSyncEngine.Files
    init(directory: URL, identity: ICloudConflictReviewIdentity, draftID: UUID = UUID()) throws {
        try Self.validate(identity)
        self.identity = identity; self.draftID = draftID
        pagePrefix = "page-review-" + (try Self.key(PageScope(scope: identity.scope, pageID: identity.pageID))) + "-"
        files = try ICloudSyncEngine.Files(directory: directory,
            name: pagePrefix + (try Self.key(identity)) + "-" + draftID.uuidString.lowercased() + ".json", createParents: true)
    }
    func load() throws -> String? { try readDraft(filename(identity: identity, id: draftID), expected: identity)?.text }
    func load(_ saved: Summary) throws -> String? {
        guard saved.identity.scope == identity.scope, saved.identity.pageID == identity.pageID,
              saved.id == (try filename(identity: saved.identity, id: saved.draftID)) else { throw ICloudPageConflictError.invalidDraft }
        return try readDraft(saved.id, expected: saved.identity)?.text
    }
    func listing() throws -> Listing {
        var summaries: [Summary] = [], failures = 0
        for name in try files.siblingNames(prefix: pagePrefix) {
            do {
                if let draft = try readDraft(name, expected: nil) {
                    summaries.append(Summary(id: name, draftID: draft.id, identity: draft.identity,
                        updatedAt: draft.updatedAt, preview: String(draft.text.prefix(100)), matchesCurrentComparison: draft.identity == identity))
                }
            } catch { failures += 1 }
        }
        summaries.sort { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt }
        return Listing(drafts: summaries, unreadableCount: failures)
    }
    func save(_ text: String) throws {
        guard text.utf8.count <= 8 * 1024 * 1024 else { throw ICloudPageConflictError.invalidDraft }
        _ = try load()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try files.write(encoder.encode(Draft(identity: identity, id: draftID, text: text, updatedAt: Date())))
    }
    private func readDraft(_ name: String, expected: ICloudConflictReviewIdentity?) throws -> Draft? {
        guard let data = try files.readSibling(name) else { return nil }
        let draft = try JSONDecoder().decode(Draft.self, from: data)
        try Self.validate(draft.identity)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard draft.schemaVersion == 1, draft.identity.scope == identity.scope, draft.identity.pageID == identity.pageID,
              expected.map({ $0 == draft.identity }) ?? true,
              try filename(identity: draft.identity, id: draft.id) == name,
              draft.updatedAt.timeIntervalSince1970.isFinite, draft.text.utf8.count <= 8 * 1024 * 1024,
              try encoder.encode(draft) == data else { throw ICloudPageConflictError.invalidDraft }
        return draft
    }
    private func filename(identity: ICloudConflictReviewIdentity, id: UUID) throws -> String {
        pagePrefix + (try Self.key(identity)) + "-" + id.uuidString.lowercased() + ".json"
    }
    private static func key<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return ICloudPageConflict.digest(try encoder.encode(value))
    }
    private static func validate(_ identity: ICloudConflictReviewIdentity) throws {
        _ = try ICloudSyncScope(accountID: identity.scope.accountID, libraryID: identity.scope.libraryID)
        guard identity.localRevision != identity.remoteRevision,
              [identity.localDigest, identity.remoteDigest].allSatisfy({ digest in
                  digest.utf8.count == 64 && digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
              }) else { throw ICloudPageConflictError.invalidDraft }
    }
}
