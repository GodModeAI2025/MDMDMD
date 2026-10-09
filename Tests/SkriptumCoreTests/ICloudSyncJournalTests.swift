import Foundation
import Darwin
import Testing
@testable import SkriptumCore

struct ICloudSyncJournalTests {
    private func root() throws -> URL {
        let value = URL(fileURLWithPath: "/private/tmp/ICloudJournal-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return value
    }
    private func scope(account: String = "owned-account", library: UUID = UUID()) throws -> ICloudSyncScope {
        try ICloudSyncScope(accountID: account, libraryID: library)
    }
    private func change(id: UUID = UUID(), revision: UUID = UUID(), payload: String = "e\u{301}\r\n🦊") -> ICloudSyncChange {
        ICloudSyncChange(recordID: ICloudSyncRecordID(kind: .page, id: id), revisionID: revision, operation: .upsert, payload: Data(payload.utf8))
    }

    @Test func largeImageSurvivesRestartWhileDocumentBudgetRemainsBounded() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let identity = try scope()
        let bytes = Data(repeating: 0xA5, count: 9 * 1024 * 1024)
        let image = ICloudSyncChange(recordID: .init(kind: .image, id: UUID()), revisionID: UUID(), operation: .upsert, payload: bytes)
        let journal = try ICloudSyncJournal(directory: directory, scope: identity)
        try journal.enqueue(image)
        let reopened = try ICloudSyncJournal(directory: directory, scope: identity)
        #expect(try reopened.pendingBatch() == [image])
        #expect(throws: ICloudSyncJournalError.batchLimitTooSmall) { try reopened.pendingBatch(maximumPayloadBytes: 8 * 1024 * 1024) }
        let oversizedPage = ICloudSyncChange(recordID: .init(kind: .page, id: UUID()), revisionID: UUID(), operation: .upsert, payload: bytes)
        #expect(throws: ICloudSyncJournalError.invalidChange) { try reopened.enqueue(oversizedPage) }
        #expect(try reopened.pendingCount() == 1)
    }

    @Test func restartRetainsExactPendingRevisionAndPayload() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let identity = try scope(), original = change()
        let journal = try ICloudSyncJournal(directory: directory, scope: identity)
        try journal.enqueue(original)
        let reopened = try ICloudSyncJournal(directory: directory, scope: identity)
        #expect(try reopened.pendingBatch() == [original])
        #expect(try reopened.acknowledge(recordID: original.recordID, revisionID: original.revisionID))
        #expect(try ICloudSyncJournal(directory: directory, scope: identity).pendingBatch().isEmpty)
    }

    @Test func lateAcknowledgementCannotEraseNewerEdit() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try ICloudSyncJournal(directory: directory, scope: scope())
        let old = change(), newer = change(id: old.recordID.id, payload: "New local edit")
        try journal.enqueue(old)
        let inFlight = try journal.pendingBatch()
        try journal.enqueue(newer)
        let bytes = try Data(contentsOf: journal.fileURL)
        #expect(try journal.acknowledge(recordID: inFlight[0].recordID, revisionID: inFlight[0].revisionID) == false)
        #expect(try Data(contentsOf: journal.fileURL) == bytes)
        #expect(try journal.pendingBatch() == [newer])
    }

    @Test func accountAndLibraryNamespacesNeverConsumeEachOthersChanges() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let library = UUID(), original = change()
        let a = try ICloudSyncJournal(directory: directory, scope: scope(account: "account-a", library: library))
        let b = try ICloudSyncJournal(directory: directory, scope: scope(account: "account-b", library: library))
        let sibling = try ICloudSyncJournal(directory: directory, scope: scope(account: "account-a"))
        try a.enqueue(original)
        #expect(try b.pendingBatch().isEmpty)
        #expect(try sibling.pendingBatch().isEmpty)
        #expect(try b.acknowledge(recordID: original.recordID, revisionID: original.revisionID) == false)
        #expect(try a.pendingBatch() == [original])
        #expect(a.fileURL != b.fileURL && a.fileURL != sibling.fileURL)
    }

    @Test func deletionIsDurableTombstoneAndOldSaveAckDoesNotEraseIt() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let identity = try scope(), original = change()
        let journal = try ICloudSyncJournal(directory: directory, scope: identity)
        try journal.enqueue(original)
        let deletion = ICloudSyncChange(recordID: original.recordID, revisionID: UUID(), operation: .tombstone, payload: Data())
        try journal.enqueue(deletion)
        let reopened = try ICloudSyncJournal(directory: directory, scope: identity)
        #expect(try reopened.pendingBatch() == [deletion])
        #expect(try reopened.acknowledge(recordID: original.recordID, revisionID: original.revisionID) == false)
        #expect(try reopened.pendingBatch().first?.operation == .tombstone)
    }

    @Test func deterministicBatchBoundsDoNotDropRemainder() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try ICloudSyncJournal(directory: directory, scope: scope())
        let ids = (1...5).map { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", $0))! }
        let values = ids.map { change(id: $0, payload: "1234") }
        for value in values.reversed() { try journal.enqueue(value) }
        #expect(try journal.pendingBatch(limit: 2, maximumPayloadBytes: 8) == Array(values.prefix(2)))
        #expect(try journal.pendingBatch(limit: 5, maximumPayloadBytes: 8) == Array(values.prefix(2)))
        #expect(try journal.pendingBatch().count == 5)
        #expect(throws: ICloudSyncJournalError.invalidBatch) { try journal.pendingBatch(limit: 0) }
        #expect(throws: ICloudSyncJournalError.batchLimitTooSmall) { try journal.pendingBatch(maximumPayloadBytes: 3) }
    }

    @Test func sameRevisionCannotAcquireDifferentPayloadOrOperation() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try ICloudSyncJournal(directory: directory, scope: scope()), original = change()
        try journal.enqueue(original)
        let bytes = try Data(contentsOf: journal.fileURL)
        try journal.enqueue(original)
        #expect(try Data(contentsOf: journal.fileURL) == bytes)
        let rewritten = change(id: original.recordID.id, revision: original.revisionID, payload: "Rewritten")
        #expect(throws: ICloudSyncJournalError.revisionPayloadMismatch) { try journal.enqueue(rewritten) }
        #expect(try Data(contentsOf: journal.fileURL) == bytes)
    }

    @Test func failedAtomicWriteKeepsPreviousQueueAndBytes() throws {
        let directory = try root(); defer { chmod(directory.path, 0o700); try? FileManager.default.removeItem(at: directory) }
        let journal = try ICloudSyncJournal(directory: directory, scope: scope()), original = change()
        try journal.enqueue(original)
        let bytes = try Data(contentsOf: journal.fileURL)
        #expect(chmod(directory.path, 0o500) == 0)
        #expect(throws: ICloudSyncJournalError.persistence) { try journal.enqueue(change()) }
        #expect(try Data(contentsOf: journal.fileURL) == bytes)
        #expect(try journal.pendingBatch() == [original])
    }

    @Test func corruptOrLinkedJournalFailsClosedWithoutReplacingEvidence() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let identity = try scope(), journal = try ICloudSyncJournal(directory: directory, scope: identity)
        try journal.enqueue(change())
        let bad = Data("broken journal".utf8)
        try bad.write(to: journal.fileURL)
        #expect(throws: ICloudSyncJournalError.invalidJournal) { try ICloudSyncJournal(directory: directory, scope: identity) }
        #expect(try Data(contentsOf: journal.fileURL) == bad)
        try FileManager.default.removeItem(at: journal.fileURL)
        let untouched = directory.appendingPathComponent("untouched")
        try Data("local document".utf8).write(to: untouched)
        try FileManager.default.createSymbolicLink(at: journal.fileURL, withDestinationURL: untouched)
        #expect(throws: ICloudSyncJournalError.unsafeFile) { try ICloudSyncJournal(directory: directory, scope: identity) }
        #expect(try Data(contentsOf: untouched) == Data("local document".utf8))
    }

    @Test func separateInstancesSerializeWithoutLostPendingChanges() async throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let identity = try scope()
        let first = try ICloudSyncJournal(directory: directory, scope: identity)
        let second = try ICloudSyncJournal(directory: directory, scope: identity)
        let values = (0..<24).map { _ in change() }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, value) in values.enumerated() {
                group.addTask { try (index.isMultiple(of: 2) ? first : second).enqueue(value) }
            }
            try await group.waitForAll()
        }
        #expect(Set(try first.pendingBatch().map(\.revisionID)) == Set(values.map(\.revisionID)))
    }

    @Test func exactPendingLookupFindsConflictOutsideMaximumUploadBatch() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try ICloudSyncJournal(directory: directory, scope: scope())
        let values = (1...129).map { number in
            change(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", number))!, payload: "x")
        }
        for value in values { try journal.enqueue(value) }
        let last = values[128]
        #expect(try journal.pendingBatch(limit: 128).contains(last) == false)
        let bytes = try Data(contentsOf: journal.fileURL)
        #expect(try journal.pendingChange(recordID: last.recordID) == last)
        #expect(try journal.pendingChange(recordID: ICloudSyncRecordID(kind: .page, id: UUID())) == nil)
        #expect(try Data(contentsOf: journal.fileURL) == bytes)
    }
}
