import Foundation
import Testing
@testable import SkriptumCore

@MainActor struct ICloudMetadataMergeTests {
    private func store() throws -> (URL, LibraryStore) {
        let root = URL(fileURLWithPath: "/private/tmp/ICloudMetadata-" + UUID().uuidString)
        return (root, try LibraryStore(directory: root))
    }
    private func encoded<T: Codable & Sendable & Identifiable>(_ value: T, kind: ICloudSyncRecordKind,
        base: T? = nil) throws -> ICloudSyncChange where T.ID == UUID {
        let digest = try base.map { try ICloudMetadataPayload<T>.digest(of: $0) }
        let payload = try ICloudMetadataPayload(value: value, baseDigest: digest)
        return ICloudSyncChange(recordID: .init(kind: kind, id: value.id), revisionID: try payload.revisionID(), operation: .upsert, payload: try payload.encoded())
    }

    @Test func projectionSpaceWrapperRoundTripsExactUTF8AndReplaysIdempotently() throws {
        let (root, target) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        var initial = LibrarySnapshot(); let space = Space(title: "e\u{301}\r\n🦊")
        initial.spaces = [space]
        let changes = try ICloudLibraryProjection.changes(from: LibrarySnapshot(), to: initial)
        let change = try #require(changes.first)
        let wrapper = try ICloudMetadataPayload<Space>.decode(change.payload)
        #expect(wrapper.schemaVersion == 1 && wrapper.baseDigest == nil)
        #expect(wrapper.value.title.utf8.elementsEqual(space.title.utf8))
        #expect(try ICloudMetadataMerge.apply(change, to: target) == .inserted)
        #expect(try ICloudMetadataMerge.apply(change, to: target) == .unchanged)
        #expect(target.snapshot.spaces[0].title.utf8.elementsEqual(space.title.utf8))
    }

    @Test func causalSpaceUpdateUsesExactBaseDigestAndPreservesOtherSpaceOrder() throws {
        let (root, target) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try target.createSpace(title: "First"), second = try target.createSpace(title: "Second")
        let before = target.snapshot; var current = before; current.spaces[0].title = "Renamed"
        let change = try #require(try ICloudLibraryProjection.changes(from: before, to: current).first)
        let wrapper = try ICloudMetadataPayload<Space>.decode(change.payload)
        #expect(wrapper.baseDigest == (try ICloudMetadataPayload<Space>.digest(of: first)))
        #expect(try ICloudMetadataMerge.apply(change, to: target) == .advanced)
        #expect(target.snapshot.spaces.map(\.id) == [first.id, second.id])
        #expect(target.snapshot.spaces[0].title == "Renamed")
    }

    @Test func divergentSpaceMetadataReturnsConflictWithoutDiskMutation() throws {
        let (root, target) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try target.createSpace(title: "Original")
        var local = target.snapshot; local.spaces[0].title = "Local change"; try target.commit(local)
        var remote = original; remote.title = "Remote change"
        let bytes = try Data(contentsOf: root.appendingPathComponent("library.json"))
        #expect(try ICloudMetadataMerge.apply(encoded(remote, kind: .space, base: original), to: target) == .conflict)
        #expect(try Data(contentsOf: root.appendingPathComponent("library.json")) == bytes)
        #expect(target.snapshot.spaces[0].title == "Local change")
    }

    @Test func commentInsertAndCausalUpdateValidatePageDependencies() throws {
        let (root, target) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let space = try target.createSpace(title: "Writing"), page = try target.createPage(spaceID: space.id, title: "Page")
        let comment = Comment(pageID: page.id, blockID: nil, body: "e\u{301}\r\n🦊", author: "Writer")
        #expect(try ICloudMetadataMerge.apply(encoded(comment, kind: .comment), to: target) == .inserted)
        var update = comment; update.body = "New comment"
        #expect(try ICloudMetadataMerge.apply(encoded(update, kind: .comment, base: comment), to: target) == .advanced)
        #expect(target.snapshot.comments[0].body == update.body)
        let orphan = Comment(pageID: UUID(), blockID: nil, body: "Unresolved page", author: "Writer")
        let bytes = try Data(contentsOf: root.appendingPathComponent("library.json"))
        #expect(throws: LibraryError.invalidLibrary) { try ICloudMetadataMerge.apply(encoded(orphan, kind: .comment), to: target) }
        #expect(try Data(contentsOf: root.appendingPathComponent("library.json")) == bytes)
    }

    @Test func historicalRevisionRoundTripsButSameIDBytesCannotBeRewritten() throws {
        let (root, target) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let space = try target.createSpace(title: "Writing"), page = try target.createPage(spaceID: space.id, title: "Page", markdown: "Old text")
        let revision = Revision(page: page, author: "Writer", capturedAt: Date(timeIntervalSince1970: 100))
        #expect(try ICloudMetadataMerge.apply(encoded(revision, kind: .revision), to: target) == .inserted)
        #expect(try ICloudMetadataMerge.apply(encoded(revision, kind: .revision), to: target) == .unchanged)
        var rewrite = revision; rewrite.author = "Different author"
        let bytes = try Data(contentsOf: root.appendingPathComponent("library.json"))
        #expect(throws: ICloudMetadataMergeError.immutableRevision) { try ICloudMetadataMerge.apply(encoded(rewrite, kind: .revision, base: revision), to: target) }
        #expect(try Data(contentsOf: root.appendingPathComponent("library.json")) == bytes)
        var altered = target.snapshot; altered.revisions[0] = rewrite
        #expect(throws: LibraryError.invalidLibrary) { try ICloudLibraryProjection.changes(from: target.snapshot, to: altered) }
    }

    @Test func wrongRecordIdentityDigestAndKindRejectBeforeAnyWrite() throws {
        let (root, target) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try target.createSpace(title: "Existing"), valid = try encoded(original, kind: .space)
        let bytes = try Data(contentsOf: root.appendingPathComponent("library.json"))
        let wrongID = ICloudSyncChange(recordID: .init(kind: .space, id: UUID()), revisionID: valid.revisionID, operation: .upsert, payload: valid.payload)
        #expect(throws: ICloudMetadataMergeError.identityMismatch) { try ICloudMetadataMerge.apply(wrongID, to: target) }
        let wrongRevision = ICloudSyncChange(recordID: valid.recordID, revisionID: UUID(), operation: .upsert, payload: valid.payload)
        #expect(throws: ICloudMetadataMergeError.revisionMismatch) { try ICloudMetadataMerge.apply(wrongRevision, to: target) }
        let wrongKind = ICloudSyncChange(recordID: .init(kind: .image, id: original.id), revisionID: valid.revisionID, operation: .upsert, payload: valid.payload)
        #expect(throws: ICloudMetadataMergeError.unsupportedKind) { try ICloudMetadataMerge.apply(wrongKind, to: target) }
        #expect(try Data(contentsOf: root.appendingPathComponent("library.json")) == bytes)
    }

    @Test func malformedWrapperAndDigestDoNotEnterLibrary() throws {
        let space = Space(title: "Metadata")
        #expect(throws: ICloudMetadataMergeError.invalidPayload) { try ICloudMetadataPayload(value: space, baseDigest: "not-a-digest") }
        let wrapper = try ICloudMetadataPayload(value: space, baseDigest: nil)
        var object = try #require(try JSONSerialization.jsonObject(with: wrapper.encoded()) as? [String: Any])
        object["schemaVersion"] = 2
        #expect(throws: ICloudMetadataMergeError.invalidPayload) { try ICloudMetadataPayload<Space>.decode(JSONSerialization.data(withJSONObject: object)) }
        object["schemaVersion"] = 1; object["providerToken"] = "must-not-be-a-field"
        #expect(throws: ICloudMetadataMergeError.invalidPayload) { try ICloudMetadataPayload<Space>.decode(JSONSerialization.data(withJSONObject: object)) }
    }

    @Test func ancestryFreeTombstoneRemainsPendingAndNeverHardDeletes() throws {
        let (root, target) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try target.createSpace(title: "Retained")
        let change = try #require(try ICloudLibraryProjection.changes(from: target.snapshot, to: LibrarySnapshot()).first)
        let bytes = try Data(contentsOf: root.appendingPathComponent("library.json"))
        #expect(try ICloudMetadataMerge.apply(change, to: target) == .pendingTombstone)
        #expect(try Data(contentsOf: root.appendingPathComponent("library.json")) == bytes)
        #expect(target.snapshot.spaces.count == 1)
    }

    @Test func activeEditingPreventsMetadataApplicationAndPreservesDraft() throws {
        let (root, target) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let space = try target.createSpace(title: "Writing"), page = try target.createPage(spaceID: space.id, title: "Page", markdown: "Saved")
        let token = try target.beginEditing(pageID: page.id, baseRevision: page.revision)
        try target.updateEditing(token, markdown: "Unfinished private draft")
        var updated = space; updated.title = "Incoming title"
        let bytes = try Data(contentsOf: root.appendingPathComponent("library.json"))
        #expect(throws: LibraryError.editInProgress) { try ICloudMetadataMerge.apply(encoded(updated, kind: .space, base: space), to: target) }
        #expect(try Data(contentsOf: root.appendingPathComponent("library.json")) == bytes)
        #expect(target.snapshot.pages[0].markdown == "Unfinished private draft")
    }

    @Test func causalDigestUsesExactUTF8RatherThanUnicodeEquality() throws {
        let (root, target) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let local = try target.createSpace(title: "e\u{301}")
        var differentBase = local; differentBase.title = "é"
        #expect(local == differentBase)
        #expect(try ICloudMetadataPayload<Space>.digest(of: local) != ICloudMetadataPayload<Space>.digest(of: differentBase))
        var remote = differentBase; remote.title = "Changed remotely"
        #expect(try ICloudMetadataMerge.apply(encoded(remote, kind: .space, base: differentBase), to: target) == .conflict)
        #expect(target.snapshot.spaces[0].title.utf8.elementsEqual(local.title.utf8))
    }
}
