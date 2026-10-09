import Foundation
import CloudKit
import CryptoKit
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

#if DEBUG && SWIFT_PACKAGE
private struct ICloudEngineFixture {
    let root: URL
    let directory: URL
    let journal: ICloudSyncJournal
    let scope: ICloudSyncScope
    init() throws {
        root = URL(fileURLWithPath: "/private/tmp/ScriptumICloudEngine-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        directory = root.appendingPathComponent("State")
        scope = try ICloudSyncScope(accountID: "owned-test-account", libraryID: UUID())
        journal = try ICloudSyncJournal(directory: root.appendingPathComponent("Outbox"), scope: scope)
    }
    func engine() throws -> ICloudSyncEngine {
        try ICloudSyncEngine(containerIdentifier: "iCloud.com.mobilebox.Skriptum", journal: journal, directory: directory)
    }
    func record(id: UUID, revision: UUID, payload: Data, libraryID: UUID? = nil, kind: String = "page") throws -> CKRecord {
        let asset = root.appendingPathComponent("asset-" + UUID().uuidString)
        try payload.write(to: asset)
        let zone = CKRecordZone.ID(zoneName: "Scriptum-" + scope.libraryID.uuidString.lowercased(), ownerName: CKCurrentUserDefaultName)
        let record = CKRecord(recordType: "ScriptumItemV1", recordID: CKRecord.ID(recordName: kind + ":" + id.uuidString.lowercased(), zoneID: zone))
        record["libraryID"] = (libraryID ?? scope.libraryID).uuidString.lowercased() as CKRecordValue
        record["kind"] = kind as CKRecordValue; record["uuid"] = id.uuidString.lowercased() as CKRecordValue
        record["revision"] = revision.uuidString.lowercased() as CKRecordValue
        record["operation"] = "upsert" as CKRecordValue
        record["sha256"] = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined() as CKRecordValue
        record["payload"] = CKAsset(fileURL: asset)
        return record
    }
    func persistedBytes() throws -> [Data] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }.map { try Data(contentsOf: $0) }
    }
}

@Test func iCloudEngineLargeImageAssetSurvivesBorrowedFileRemoval() async throws {
    let fixture = try ICloudEngineFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let engine = try fixture.engine()
    let payload = Data(repeating: 0xA5, count: 9 * 1024 * 1024)
    let record = try fixture.record(id: UUID(), revision: UUID(), payload: payload, kind: "image")
    try await engine.verificationRetainIncoming([record])
    let asset = try #require((record["payload"] as? CKAsset)?.fileURL)
    try FileManager.default.removeItem(at: asset)
    let restarted = try fixture.engine()
    let inbox = await restarted.incomingSnapshot()
    #expect(inbox.count == 1)
    #expect(inbox.first?.change?.payload == payload)
    #expect(inbox.first?.change?.recordID.kind == .image)
    let page = try fixture.record(id: UUID(), revision: UUID(), payload: payload)
    do { try await restarted.verificationRetainIncoming([page]); Issue.record("Oversized page accepted") }
    catch { #expect(error is ICloudSyncEngineError) }
    #expect(await restarted.incomingSnapshot().count == 1)
}

@Test func iCloudEngineInboxCopiesBorrowedAssetsDurablyWithoutActivation() async throws {
    let fixture = try ICloudEngineFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let engine = try fixture.engine(), id = UUID(), revision = UUID()
    let payload = Data("e\u{301}\r\n🦊\r\n".utf8)
    let record = try fixture.record(id: id, revision: revision, payload: payload)
    try await engine.verificationRetainIncoming([record])
    let asset = try #require((record["payload"] as? CKAsset)?.fileURL)
    try FileManager.default.removeItem(at: asset)
    let restarted = try fixture.engine()
    let inbox = await restarted.incomingSnapshot()
    #expect(inbox.count == 1)
    #expect(inbox[0].change?.payload == payload)
    #expect(inbox[0].change?.revisionID == revision)
    #expect(await restarted.status == .inactive)
    #expect(try fixture.journal.pendingBatch().isEmpty)
}

@Test func iCloudEngineInvalidRemoteScopeAndDigestPreserveDurableInbox() async throws {
    let fixture = try ICloudEngineFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let engine = try fixture.engine(), payload = Data("ordinary source".utf8)
    try await engine.verificationRetainIncoming([fixture.record(id: UUID(), revision: UUID(), payload: payload)])
    let before = try fixture.persistedBytes()
    let wrongScope = try fixture.record(id: UUID(), revision: UUID(), payload: payload, libraryID: UUID())
    let wrongDigest = try fixture.record(id: UUID(), revision: UUID(), payload: payload)
    wrongDigest["sha256"] = String(repeating: "0", count: 64) as CKRecordValue
    for record in [wrongScope, wrongDigest] {
        do { try await engine.verificationRetainIncoming([record]); Issue.record("Invalid remote record entered inbox") }
        catch { #expect(error is ICloudSyncEngineError) }
        #expect(try fixture.persistedBytes() == before)
    }
    #expect(await engine.incomingSnapshot().count == 1)
}

@Test func iCloudEngineIncomingAcknowledgementIsExactRevisionAndNeverOutboxAcknowledgement() async throws {
    let fixture = try ICloudEngineFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let engine = try fixture.engine(), id = UUID(), first = UUID(), second = UUID(), local = UUID()
    let recordID = ICloudSyncRecordID(kind: .page, id: id)
    try fixture.journal.enqueue(ICloudSyncChange(recordID: recordID, revisionID: local, operation: .upsert, payload: Data("local".utf8)))
    try await engine.verificationRetainIncoming([
        fixture.record(id: id, revision: first, payload: Data("remote first".utf8)),
        fixture.record(id: id, revision: second, payload: Data("remote second".utf8))
    ])
    try await engine.acknowledgeIncoming(recordID: recordID, revisionID: first)
    let restarted = try fixture.engine(), inbox = await restarted.incomingSnapshot()
    #expect(inbox.map { $0.change?.revisionID } == [second])
    #expect(try fixture.journal.pendingBatch().map(\.revisionID) == [local])
}

@Test func iCloudEngineSavedMetadataWithoutAssetAcknowledgesExactSentChange() async throws {
    let fixture = try ICloudEngineFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let engine = try fixture.engine(), id = UUID(), revision = UUID(), payload = Data("sent source".utf8)
    let change = ICloudSyncChange(recordID: ICloudSyncRecordID(kind: .page, id: id), revisionID: revision, operation: .upsert, payload: payload)
    try fixture.journal.enqueue(change); try await engine.verificationTrackSent(change)
    let record = try fixture.record(id: id, revision: revision, payload: payload)
    record["payload"] = nil
    try await engine.verificationHandleSaved([record])
    #expect(try fixture.journal.pendingBatch().isEmpty)
    #expect(try fixture.persistedBytes().count == 1)
}

@Test func iCloudEngineSavedMetadataWithMismatchedDigestNeverAcknowledges() async throws {
    let fixture = try ICloudEngineFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let engine = try fixture.engine(), id = UUID(), revision = UUID(), payload = Data("sent source".utf8)
    let change = ICloudSyncChange(recordID: ICloudSyncRecordID(kind: .page, id: id), revisionID: revision, operation: .upsert, payload: payload)
    try fixture.journal.enqueue(change); try await engine.verificationTrackSent(change)
    let record = try fixture.record(id: id, revision: revision, payload: payload)
    record["payload"] = nil; record["sha256"] = String(repeating: "0", count: 64) as CKRecordValue
    do { try await engine.verificationHandleSaved([record]); Issue.record("Mismatched saved digest acknowledged local source") }
    catch { #expect(error is ICloudSyncEngineError) }
    #expect(try fixture.journal.pendingBatch() == [change])
    #expect(try fixture.persistedBytes().isEmpty)
}

@Test func iCloudEngineLateSavedMetadataPreservesNewerQueuedRevision() async throws {
    let fixture = try ICloudEngineFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let engine = try fixture.engine(), id = UUID(), sentRevision = UUID(), nextRevision = UUID()
    let recordID = ICloudSyncRecordID(kind: .page, id: id)
    let sent = ICloudSyncChange(recordID: recordID, revisionID: sentRevision, operation: .upsert, payload: Data("sent".utf8))
    let newer = ICloudSyncChange(recordID: recordID, revisionID: nextRevision, operation: .upsert, payload: Data("newer local".utf8))
    try fixture.journal.enqueue(sent); try await engine.verificationTrackSent(sent)
    try fixture.journal.enqueue(newer)
    let record = try fixture.record(id: id, revision: sentRevision, payload: sent.payload); record["payload"] = nil
    try await engine.verificationHandleSaved([record])
    #expect(try fixture.journal.pendingBatch() == [newer])
}

@Test func iCloudEngineReusedIncomingRevisionWithDifferentBytesIsRejectedWithoutMutation() async throws {
    let fixture = try ICloudEngineFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let engine = try fixture.engine(), id = UUID(), revision = UUID()
    try await engine.verificationRetainIncoming([fixture.record(id: id, revision: revision, payload: Data("first".utf8))])
    let before = try fixture.persistedBytes()
    do { try await engine.verificationRetainIncoming([fixture.record(id: id, revision: revision, payload: Data("different".utf8))]); Issue.record("Immutable incoming revision silently accepted different bytes") }
    catch { #expect(error is ICloudSyncEngineError) }
    #expect(try fixture.persistedBytes() == before)
    #expect(await engine.incomingSnapshot().first?.change?.payload == Data("first".utf8))
}
#endif
