import Foundation
import Darwin
import Testing
@testable import SkriptumCore

@MainActor struct ICloudLibraryJournalBridgeTests {
    private func fixture() throws -> (URL, ICloudSyncJournal, LibrarySnapshot) {
        let root = URL(fileURLWithPath: "/private/tmp/ICloudBridge-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let journal = try ICloudSyncJournal(directory: root, scope: ICloudSyncScope(accountID: "owned-account", libraryID: UUID()))
        let space = Space(title: "e\u{301}")
        var snapshot = LibrarySnapshot(); snapshot.spaces = [space]
        snapshot.pages = [Page(spaceID: space.id, title: "Local page", markdown: "e\u{301}\r\n🦊")]
        return (root, journal, snapshot)
    }
    private func edited(_ snapshot: LibrarySnapshot) -> LibrarySnapshot {
        var result = snapshot; result.pages[0].revision = UUID()
        result.pages[0].blocks = [Block(markdown: "New exact text\r\n🦊")]
        return result
    }
    private func clearConfirmed(_ journal: ICloudSyncJournal) throws {
        for change in try journal.pendingBatch() { try journal.acknowledge(recordID: change.recordID, revisionID: change.revisionID) }
    }

    @Test func explicitBootstrapQueuesAllDocumentRecordsAndPersistsExactBaseline() throws {
        let (root, journal, snapshot) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bridge = try ICloudLibraryJournalBridge(journal: journal)
        #expect(try bridge.lastProjectedSnapshot() == nil)
        #expect(try bridge.bootstrap(snapshot) == 2)
        let page = try #require(try journal.pendingChange(recordID: .init(kind: .page, id: snapshot.pages[0].id)))
        #expect(try ICloudPagePayload.decode(page.payload, expectedPageID: page.recordID.id, expectedRevision: page.revisionID).baseRevision == nil)
        #expect(try bridge.lastProjectedSnapshot() == snapshot)
        let checkpoint = try Data(contentsOf: bridge.checkpointURL)
        #expect(try bridge.bootstrap(snapshot) == 0)
        #expect(try Data(contentsOf: bridge.checkpointURL) == checkpoint)
    }

    @Test func committedTransitionKeepsPageAncestryAcrossRestart() throws {
        let (root, journal, before) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bridge = try ICloudLibraryJournalBridge(journal: journal)
        try bridge.bootstrap(before); try clearConfirmed(journal)
        let current = edited(before)
        #expect(try bridge.project(from: before, to: current) == 1)
        let change = try #require(try journal.pendingChange(recordID: .init(kind: .page, id: before.pages[0].id)))
        let page = try ICloudPagePayload.decode(change.payload, expectedPageID: change.recordID.id, expectedRevision: change.revisionID)
        #expect(page.baseRevision == before.pages[0].revision)
        #expect(page.page.blocks[0].markdown.utf8.elementsEqual(current.pages[0].blocks[0].markdown.utf8))
        #expect(try ICloudLibraryJournalBridge(journal: journal).lastProjectedSnapshot() == current)
    }

    @Test func partialQueueCrashReplayKeepsSameRevisionAndAncestorBytes() throws {
        let (root, journal, before) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bridge = try ICloudLibraryJournalBridge(journal: journal)
        try bridge.bootstrap(before); try clearConfirmed(journal)
        var current = edited(before); current.spaces[0].title = "Renamed"
        let expected = try ICloudLibraryProjection.changes(from: before, to: current)
        try journal.enqueue(expected[0]) // Simulated termination before later enqueue/checkpoint.
        let reloaded = try ICloudSyncJournal(directory: root, scope: journal.scope)
        let recovered = try ICloudLibraryJournalBridge(journal: reloaded)
        #expect(try recovered.lastProjectedSnapshot() == before)
        #expect(try recovered.project(from: before, to: current) == expected.count)
        #expect(try reloaded.pendingBatch() == expected)
        #expect(try recovered.lastProjectedSnapshot() == current)
    }

    @Test func checkpointFailureAfterAllEnqueuesRetainsReplayableOldBaseline() throws {
        let (root, journal, before) = try fixture()
        defer { chmod(root.path, 0o700); try? FileManager.default.removeItem(at: root) }
        let bridge = try ICloudLibraryJournalBridge(journal: journal)
        try bridge.bootstrap(before); try clearConfirmed(journal)
        var current = edited(before); current.spaces[0].title = "Renamed"
        let expected = try ICloudLibraryProjection.changes(from: before, to: current)
        for change in expected { try journal.enqueue(change) }
        let checkpoint = try Data(contentsOf: bridge.checkpointURL)
        #expect(chmod(root.path, 0o500) == 0)
        #expect(throws: ICloudLibraryJournalBridgeError.persistence) { try bridge.project(from: before, to: current) }
        #expect(try Data(contentsOf: bridge.checkpointURL) == checkpoint)
        #expect(try journal.pendingBatch() == expected)
        #expect(chmod(root.path, 0o700) == 0)
        let recovered = try ICloudLibraryJournalBridge(journal: journal)
        try recovered.project(from: before, to: current)
        #expect(try recovered.lastProjectedSnapshot() == current)
        #expect(try journal.pendingBatch() == expected)
    }

    @Test func failedEnqueueNeverAdvancesCheckpoint() throws {
        let (root, journal, before) = try fixture()
        defer { chmod(root.path, 0o700); try? FileManager.default.removeItem(at: root) }
        let bridge = try ICloudLibraryJournalBridge(journal: journal)
        try bridge.bootstrap(before); try clearConfirmed(journal)
        let checkpoint = try Data(contentsOf: bridge.checkpointURL)
        #expect(chmod(root.path, 0o500) == 0)
        #expect(throws: ICloudSyncJournalError.persistence) { try bridge.project(from: before, to: edited(before)) }
        #expect(try Data(contentsOf: bridge.checkpointURL) == checkpoint)
        #expect(try journal.pendingBatch().isEmpty)
    }

    @Test func staleBridgeCannotOverwriteNewerBaselineOrPendingRevision() throws {
        let (root, journal, before) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try ICloudLibraryJournalBridge(journal: journal), stale = try ICloudLibraryJournalBridge(journal: journal)
        try first.bootstrap(before)
        let current = edited(before); try first.project(from: before, to: current)
        let checkpoint = try Data(contentsOf: first.checkpointURL), pending = try journal.pendingBatch()
        #expect(throws: ICloudLibraryJournalBridgeError.baselineConflict) { try stale.project(from: before, to: edited(before)) }
        #expect(try Data(contentsOf: first.checkpointURL) == checkpoint)
        #expect(try journal.pendingBatch() == pending)
        #expect(try stale.project(from: before, to: current) == 0)
    }

    @Test func baselineCASUsesEncodedBytesRatherThanUnicodeEquivalentStrings() throws {
        let (root, journal, before) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bridge = try ICloudLibraryJournalBridge(journal: journal); try bridge.bootstrap(before)
        var canonicalEquivalent = before; canonicalEquivalent.spaces[0].title = "é"
        #expect(canonicalEquivalent == before)
        #expect(throws: ICloudLibraryJournalBridgeError.baselineConflict) { try bridge.project(from: canonicalEquivalent, to: edited(before)) }
        #expect(try bridge.lastProjectedSnapshot()?.spaces[0].title.utf8.elementsEqual(before.spaces[0].title.utf8) == true)
    }

    @Test func corruptedCheckpointIsRetainedAndPreventsFurtherProjection() throws {
        let (root, journal, before) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bridge = try ICloudLibraryJournalBridge(journal: journal); try bridge.bootstrap(before)
        let bad = Data("Broken checkpoint".utf8); try bad.write(to: bridge.checkpointURL)
        let pending = try journal.pendingBatch()
        #expect(throws: ICloudLibraryJournalBridgeError.invalidCheckpoint) { try ICloudLibraryJournalBridge(journal: journal) }
        #expect(try Data(contentsOf: bridge.checkpointURL) == bad)
        #expect(try journal.pendingBatch() == pending)
    }
}
