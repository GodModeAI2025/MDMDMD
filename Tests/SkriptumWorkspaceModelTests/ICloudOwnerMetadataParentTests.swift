import Foundation
import CloudKit
import CryptoKit
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

#if DEBUG && SWIFT_PACKAGE
private struct OwnerMetadataFixture {
    let directory: URL
    let scope: ICloudSyncScope
    let journal: ICloudSyncJournal
    let engine: ICloudSyncEngine
    var zone: CKRecordZone.ID {
        .init(zoneName: "Scriptum-" + scope.libraryID.uuidString.lowercased(), ownerName: CKCurrentUserDefaultName)
    }
    init() throws {
        directory = URL(fileURLWithPath: "/private/tmp/ScriptumOwnerMetadata-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        scope = try ICloudSyncScope(accountID: "owner-test-account", libraryID: UUID())
        journal = try ICloudSyncJournal(directory: directory.appendingPathComponent("Outbox"), scope: scope)
        engine = try ICloudSyncEngine(containerIdentifier: "iCloud.com.mobilebox.Skriptum", journal: journal,
                                     directory: directory.appendingPathComponent("State"))
    }
    func id(_ kind: ICloudSyncRecordKind, _ id: UUID) -> CKRecord.ID {
        .init(recordName: kind.rawValue + ":" + id.uuidString.lowercased(), zoneID: zone)
    }
    func stagedAssets() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("State"), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("asset-") }
    }
    func remoteRecord(_ change: ICloudSyncChange) throws -> CKRecord {
        let record = CKRecord(recordType: "ScriptumItemV1", recordID: id(change.recordID.kind, change.recordID.id))
        record["libraryID"] = scope.libraryID.uuidString.lowercased() as CKRecordValue
        record["kind"] = change.recordID.kind.rawValue as CKRecordValue
        record["uuid"] = change.recordID.id.uuidString.lowercased() as CKRecordValue
        record["revision"] = change.revisionID.uuidString.lowercased() as CKRecordValue
        record["operation"] = change.operation.rawValue as CKRecordValue
        record["sha256"] = SHA256.hash(data: change.payload).map { String(format: "%02x", $0) }.joined() as CKRecordValue
        let url = directory.appendingPathComponent("remote-payload")
        try change.payload.write(to: url)
        record["payload"] = CKAsset(fileURL: url)
        return record
    }
    func change(_ kind: String, page: Page) throws -> ICloudSyncChange {
        if kind == "revision" {
            // Revision has no public memberwise initializer outside its module.
            let encoded = try JSONSerialization.data(withJSONObject: [
                "page": JSONSerialization.jsonObject(with: JSONEncoder().encode(page)),
                "author": "Owner", "capturedAt": 0
            ])
            let value = try JSONDecoder().decode(Revision.self, from: encoded)
            let payload = try ICloudMetadataPayload(value: value, baseDigest: nil)
            return try .init(recordID: .init(kind: .revision, id: value.id), revisionID: payload.revisionID(),
                             operation: .upsert, payload: payload.encoded())
        }
        var comment = Comment(pageID: page.id, blockID: nil, body: "Owner comment", author: "Owner")
        if kind == "reply" { comment.parentCommentID = UUID() }
        let payload = try ICloudMetadataPayload(value: comment, baseDigest: nil)
        return try .init(recordID: .init(kind: .comment, id: comment.id), revisionID: payload.revisionID(),
                         operation: .upsert, payload: payload.encoded())
    }
}

@Test(arguments: ["comment", "reply", "revision"])
func ownerMetadataOutgoingRecordInheritsConfirmedPageShare(kind: String) async throws {
    let fixture = try OwnerMetadataFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let page = Page(spaceID: UUID(), title: "Already shared", markdown: "Shared text")
    let root = fixture.id(.page, page.id), change = try fixture.change(kind, page: page)
    try fixture.journal.enqueue(change)
    let record = try await fixture.engine.verificationOutgoingRecord(change) { pageID in
        #expect(pageID == page.id)
        return root
    }
    #expect(record.parent?.recordID == root)
    #expect(record.parent?.action == CKRecord.ReferenceAction.none)
    #expect(try fixture.journal.pendingBatch() == [change])
    #expect(record["uuid"] as? String == change.recordID.id.uuidString.lowercased())
    #expect(record["revision"] as? String == change.revisionID.uuidString.lowercased())
    let url = try #require((record["payload"] as? CKAsset)?.fileURL)
    #expect(try Data(contentsOf: url) == change.payload)
    await fixture.engine.stop()
}

@Test func ownerMetadataPrivatePageRemainsPrivate() async throws {
    let fixture = try OwnerMetadataFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let page = Page(spaceID: UUID(), title: "Private"), change = try fixture.change("comment", page: page)
    try fixture.journal.enqueue(change)
    let record = try await fixture.engine.verificationOutgoingRecord(change) { _ in nil }
    #expect(record.parent == nil)
    #expect(try fixture.journal.pendingBatch() == [change])
    await fixture.engine.stop()
}

@Test(arguments: [ICloudSyncRecordKind.page, .space, .image])
func ownerMetadataNeverExpandsShareToNewContent(kind: ICloudSyncRecordKind) async throws {
    let fixture = try OwnerMetadataFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let change = ICloudSyncChange(recordID: .init(kind: kind, id: UUID()), revisionID: UUID(), operation: .upsert, payload: Data("New private content".utf8))
    try fixture.journal.enqueue(change)
    let record = try await fixture.engine.verificationOutgoingRecord(change) { _ in
        Issue.record("New content must not request inherited sharing")
        return fixture.id(.space, UUID())
    }
    #expect(record.parent == nil)
    await fixture.engine.stop()
}

@Test(arguments: [true, false])
func ownerMetadataExistingRecordsKeepTheirOriginalScope(shared: Bool) async throws {
    let fixture = try OwnerMetadataFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let page = Page(spaceID: UUID(), title: "Page"), change = try fixture.change("comment", page: page)
    try fixture.journal.enqueue(change)
    let original = try await fixture.engine.verificationOutgoingRecord(change) { _ in shared ? fixture.id(.page, page.id) : nil }
    // Simulate an exact server receipt, then enqueue an edit of that record.
    try await fixture.engine.verificationHandleSaved([original])
    let current = try ICloudMetadataPayload<SkriptumCore.Comment>.decode(change.payload)
    var comment = current.value; comment.body = "Changed comment"
    let edit = try ICloudMetadataPayload(value: comment, baseDigest: ICloudMetadataPayload<SkriptumCore.Comment>.digest(of: current.value))
    let updated = try ICloudSyncChange(recordID: change.recordID, revisionID: edit.revisionID(), operation: .upsert, payload: edit.encoded())
    try fixture.journal.enqueue(updated)
    let record = try await fixture.engine.verificationOutgoingRecord(updated) { _ in
        Issue.record("Existing records must retain their native parent instead of being reparented")
        return fixture.id(.space, UUID())
    }
    #expect(record.parent?.recordID == original.parent?.recordID)
    #expect(try fixture.journal.pendingBatch() == [updated])
    await fixture.engine.stop()
}

@Test(arguments: ["id", "revision", "payload"])
func ownerMetadataRejectsUnboundPayloadBeforeLookup(mismatch: String) async throws {
    let fixture = try OwnerMetadataFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let original = try fixture.change("comment", page: Page(spaceID: UUID(), title: "Shared"))
    let change = ICloudSyncChange(recordID: mismatch == "id" ? .init(kind: .comment, id: UUID()) : original.recordID,
        revisionID: mismatch == "revision" ? UUID() : original.revisionID, operation: .upsert,
        payload: mismatch == "payload" ? Data("{}".utf8) : original.payload)
    try fixture.journal.enqueue(change)
    await #expect(throws: (any Error).self) {
        _ = try await fixture.engine.verificationOutgoingRecord(change) { _ in
            Issue.record("Invalid metadata reached the share lookup")
            return nil
        }
    }
    #expect(try fixture.stagedAssets().isEmpty)
    #expect(try fixture.journal.pendingBatch() == [change])
}

@Test func ownerMetadataRejectedAccessRetainsOutboxAndStagesNoAsset() async throws {
    let fixture = try OwnerMetadataFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let change = try fixture.change("comment", page: Page(spaceID: UUID(), title: "Previously shared"))
    try fixture.journal.enqueue(change)
    do {
        _ = try await fixture.engine.verificationOutgoingRecord(change) { _ in throw CKError(.permissionFailure) }
        Issue.record("Rejected share access produced an outgoing record")
    } catch { #expect((error as? CKError)?.code == .permissionFailure) }
    #expect(try fixture.stagedAssets().isEmpty)
    #expect(try fixture.journal.pendingBatch() == [change])
}

@Test func ownerMetadataStopDuringLookupCannotStageOrSendOldConnectionData() async throws {
    let fixture = try OwnerMetadataFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let page = Page(spaceID: UUID(), title: "Shared"), change = try fixture.change("comment", page: page)
    try fixture.journal.enqueue(change)
    do {
        _ = try await fixture.engine.verificationOutgoingRecord(change) { _ in
            await fixture.engine.stop()
            return fixture.id(.page, page.id)
        }
        Issue.record("Stopped connection staged a shared record")
    } catch { #expect(error as? ICloudSyncEngineError == .stopped) }
    #expect(await fixture.engine.status == .inactive)
    #expect(try fixture.stagedAssets().isEmpty)
    #expect(try fixture.journal.pendingBatch() == [change])
}

@Test func ownerMetadataEditDuringLookupKeepsOnlyLatestRevisionQueued() async throws {
    let fixture = try OwnerMetadataFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let page = Page(spaceID: UUID(), title: "Shared"), change = try fixture.change("comment", page: page)
    let payload = try ICloudMetadataPayload<SkriptumCore.Comment>.decode(change.payload)
    var value = payload.value; value.body = "Edited during validation"
    let edited = try ICloudMetadataPayload(value: value, baseDigest: nil)
    let latest = try ICloudSyncChange(recordID: change.recordID, revisionID: edited.revisionID(), operation: .upsert, payload: edited.encoded())
    try fixture.journal.enqueue(change)
    do {
        _ = try await fixture.engine.verificationOutgoingRecord(change) { _ in
            try fixture.journal.enqueue(latest)
            return fixture.id(.page, page.id)
        }
        Issue.record("Superseded comment was staged")
    } catch { #expect(error as? ICloudSyncEngineError == .stopped) }
    #expect(try fixture.stagedAssets().isEmpty)
    #expect(try fixture.journal.pendingBatch() == [latest])
}

@Test func ownerMetadataConcurrentPreparationCannotReplaceInFlightRecord() async throws {
    let fixture = try OwnerMetadataFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let page = Page(spaceID: UUID(), title: "Shared"), change = try fixture.change("comment", page: page)
    try fixture.journal.enqueue(change)
    do {
        _ = try await fixture.engine.verificationOutgoingRecord(change) { _ in
            _ = try await fixture.engine.verificationOutgoingRecord(change) { _ in fixture.id(.page, page.id) }
            return fixture.id(.page, page.id)
        }
        Issue.record("A concurrent preparation replaced an in-flight record")
    } catch { #expect(error as? ICloudSyncEngineError == .stopped) }
    #expect(try fixture.stagedAssets().count == 1)
    #expect(try fixture.journal.pendingBatch() == [change])
    await fixture.engine.stop()
    #expect(try fixture.stagedAssets().isEmpty)
}

@Test func ownerMetadataConflictDuringLookupCannotStageAnOutgoingOverwrite() async throws {
    let fixture = try OwnerMetadataFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let page = Page(spaceID: UUID(), title: "Shared"), change = try fixture.change("comment", page: page)
    let payload = try ICloudMetadataPayload<SkriptumCore.Comment>.decode(change.payload)
    var value = payload.value; value.body = "Different comment received from CloudKit"
    let remote = try ICloudMetadataPayload(value: value, baseDigest: nil)
    let incoming = try ICloudSyncChange(recordID: change.recordID, revisionID: remote.revisionID(), operation: .upsert, payload: remote.encoded())
    let record = try fixture.remoteRecord(incoming)
    try fixture.journal.enqueue(change)
    do {
        _ = try await fixture.engine.verificationOutgoingRecord(change) { _ in
            try await fixture.engine.verificationRetainIncoming([record])
            return fixture.id(.page, page.id)
        }
        Issue.record("A new CloudKit conflict was overwritten")
    } catch { #expect(error as? ICloudSyncEngineError == .stopped) }
    #expect(try fixture.stagedAssets().isEmpty)
    #expect(try fixture.journal.pendingBatch() == [change])
    #expect(await fixture.engine.unresolvedConflictCount() == 1)
    #expect(await fixture.engine.incomingSnapshot().first?.change == incoming)
}

@Test(arguments: ["task", "cloudkit"])
func ownerMetadataCancelledLookupDoesNotBecomeCloudOrStorageFailure(kind: String) async throws {
    let fixture = try OwnerMetadataFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let change = try fixture.change("comment", page: Page(spaceID: UUID(), title: "Shared"))
    try fixture.journal.enqueue(change)
    let error: any Error = kind == "task" ? CancellationError() : CKError(.operationCancelled)
    await fixture.engine.verificationOwnerLookupFailure(error)
    #expect(await fixture.engine.status == .inactive)
    #expect(await fixture.engine.lastFailure == nil)
    #expect(try fixture.journal.pendingBatch() == [change])
    #expect(try fixture.stagedAssets().isEmpty)
}

@Test func ownerMetadataLookupFailurePreservesCloudDiagnosticAndOutbox() async throws {
    let fixture = try OwnerMetadataFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let change = try fixture.change("comment", page: Page(spaceID: UUID(), title: "Shared"))
    try fixture.journal.enqueue(change)
    let error = CKError(.permissionFailure)
    await fixture.engine.verificationOwnerLookupFailure(error)
    #expect(await fixture.engine.status == .cloudUnavailable)
    #expect(await fixture.engine.lastFailure == ICloudFailureDiagnostic.describe(error))
    #expect(try fixture.journal.pendingBatch() == [change])
    #expect(try fixture.stagedAssets().isEmpty)
}

@Test func ownerMetadataAcknowledgementRequiresConfirmedParent() async throws {
    let fixture = try OwnerMetadataFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let page = Page(spaceID: UUID(), title: "Shared"), change = try fixture.change("reply", page: page)
    try fixture.journal.enqueue(change)
    let record = try await fixture.engine.verificationOutgoingRecord(change) { _ in fixture.id(.page, page.id) }
    let wrong = try #require(record.copy() as? CKRecord); wrong.parent = nil
    await #expect(throws: ICloudSyncEngineError.self) { try await fixture.engine.verificationHandleSaved([wrong]) }
    #expect(try fixture.journal.pendingBatch() == [change])
    try await fixture.engine.verificationHandleSaved([record])
    #expect(try fixture.journal.pendingBatch().isEmpty)
    #expect(try fixture.stagedAssets().isEmpty)
}

@Test(arguments: [true, false])
func ownerMetadataUsesNativePageRootOrExistingSpaceParent(pageIsRoot: Bool) throws {
    let fixture = try OwnerMetadataFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let pageID = UUID(), page = fixture.id(.page, pageID)
    let root = pageIsRoot ? page : fixture.id(.space, UUID())
    let share = CKRecord.ID(recordName: "existing-native-share", zoneID: fixture.zone)
    let rootLink = ICloudOwnerMetadataParent.Link(id: root, share: share)
    let pageLink = pageIsRoot ? rootLink : .init(id: page, parent: root)
    let request = try #require(ICloudOwnerMetadataParent.request(pageID: pageID, zone: fixture.zone) {
        $0 == page ? pageLink : $0 == root ? rootLink : nil
    })
    #expect(request.page == page)
    #expect(request.root == root)
    #expect(request.share == share)
    try ICloudOwnerMetadataParent.validate(request, page: pageLink, root: rootLink, shareID: share, isOwner: true, isPrivate: true)
}

@Test func ownerMetadataMissingOrPrivatePageHasNoShareGrant() throws {
    let fixture = try OwnerMetadataFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let pageID = UUID()
    #expect(try ICloudOwnerMetadataParent.request(pageID: pageID, zone: fixture.zone) { _ in nil } == nil)
    #expect(try ICloudOwnerMetadataParent.request(pageID: pageID, zone: fixture.zone) { .init(id: $0) } == nil)
}

@Test(arguments: ["missingRoot", "wrongRoot", "crossZone", "unsharedRoot", "nestedRoot", "otherShare", "imageRoot"])
func ownerMetadataUnprovenCachedHierarchyIsRejected(mismatch: String) throws {
    let fixture = try OwnerMetadataFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let pageID = UUID(), page = fixture.id(.page, pageID)
    let root = mismatch == "imageRoot" ? fixture.id(.image, UUID()) : fixture.id(.space, UUID())
    let share = CKRecord.ID(recordName: "existing-share", zoneID: fixture.zone)
    let other = CKRecord.ID(recordName: "other-share", zoneID: fixture.zone)
    let foreign = CKRecord.ID(recordName: root.recordName, zoneID: .init(zoneName: "other", ownerName: CKCurrentUserDefaultName))
    let pageLink = ICloudOwnerMetadataParent.Link(id: page, parent: mismatch == "crossZone" ? foreign : root,
                                                 share: mismatch == "otherShare" ? other : nil)
    let rootLink = ICloudOwnerMetadataParent.Link(id: mismatch == "wrongRoot" ? fixture.id(.space, UUID()) : root,
        parent: mismatch == "nestedRoot" ? fixture.id(.space, UUID()) : nil, share: mismatch == "unsharedRoot" ? nil : share)
    #expect(throws: ICloudSyncEngineError.self) {
        _ = try ICloudOwnerMetadataParent.request(pageID: pageID, zone: fixture.zone) {
            $0 == page ? pageLink : mismatch == "missingRoot" ? nil : rootLink
        }
    }
}

@Test(arguments: ["owner", "publicShare", "shareID", "rootShare", "pageParent", "pageID", "rootID", "nestedRoot"])
func ownerMetadataFreshNativeAccessMustMatchExactCachedGrant(mismatch: String) throws {
    let fixture = try OwnerMetadataFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let page = fixture.id(.page, UUID()), root = fixture.id(.space, UUID())
    let share = CKRecord.ID(recordName: "existing-share", zoneID: fixture.zone)
    let otherShare = CKRecord.ID(recordName: "other-share", zoneID: fixture.zone)
    let request = ICloudOwnerMetadataParent.Request(page: page, root: root, share: share)
    let freshPage = ICloudOwnerMetadataParent.Link(id: mismatch == "pageID" ? fixture.id(.page, UUID()) : page,
                                                  parent: mismatch == "pageParent" ? nil : root)
    let freshRoot = ICloudOwnerMetadataParent.Link(id: mismatch == "rootID" ? fixture.id(.space, UUID()) : root,
        parent: mismatch == "nestedRoot" ? fixture.id(.space, UUID()) : nil,
        share: mismatch == "rootShare" ? otherShare : share)
    #expect(throws: ICloudSyncEngineError.self) {
        try ICloudOwnerMetadataParent.validate(request, page: freshPage, root: freshRoot,
            shareID: mismatch == "shareID" ? otherShare : share, isOwner: mismatch != "owner", isPrivate: mismatch != "publicShare")
    }
}
#endif
