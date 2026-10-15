import Foundation
import CloudKit
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@Test(arguments: [false, true]) @MainActor
func ownerShareManagementSurvivesOrdinaryEditsWithoutChangingCreationScope(shareSpace: Bool) throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumShareManagement-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LibraryStore(directory: directory.appendingPathComponent("Library"))
    let space = try store.createSpace(title: "Shared writing")
    let page = try store.createPage(spaceID: space.id, title: "Chapter", markdown: "Original e\u{301}\r\n🦊")
    let scope = try ICloudSyncScope(accountID: "Owner", libraryID: UUID())
    let requested: ICloudShareScope = shareSpace ? .space(space.id) : .page(page.id)
    let plan = try ICloudShareRecordPlan(scope: requested, snapshot: store.snapshot)
    let receiptDirectory = directory.appendingPathComponent("Receipts")
    let receipts = try ICloudOwnerShareReceipts(directory: receiptDirectory, scope: scope)
    let operation = try receipts.begin(plan: plan, shareName: "cloudkit.share.confirmed")
    try receipts.confirm(operation)
    let confirmed = try #require(try receipts.operation(for: plan))
    let receiptFile = try #require(FileManager.default.contentsOfDirectory(at: receiptDirectory, includingPropertiesForKeys: nil).first)
    let receiptBytes = try Data(contentsOf: receiptFile)

    // Normal editor commit adds a history item. A later comment/child changes
    // the manifest further but must not silently expand an existing share.
    try store.updateWritingPage(pageID: page.id, baseRevision: page.revision, title: page.title,
        markdown: "Edited e\u{301}\r\n🦊", isFavorite: false, tags: [], trashed: false, wordGoal: 0, purpose: .writing)
    try store.addComment(Comment(pageID: page.id, blockID: nil, body: "New comment", author: "Owner"))
    _ = try store.createPage(spaceID: space.id, parentID: page.id, title: "New private child", markdown: "Keep private")
    let changed = try ICloudShareRecordPlan(scope: requested, snapshot: store.snapshot)
    #expect(changed.entries != plan.entries)
    #expect(throws: ICloudShareOwnerError.changedManifest) { try receipts.operation(for: changed) }

    let restarted = try ICloudOwnerShareReceipts(directory: receiptDirectory, scope: scope)
    #expect(try restarted.managementOperation(for: requested, snapshot: store.snapshot) == confirmed)
    #expect(try Data(contentsOf: receiptFile) == receiptBytes)
    #expect(try restarted.operation(for: plan) == confirmed)
}

@Test @MainActor func ownerShareManagementNeverAdmitsAnUnconfirmedChangedCreation() throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumShareManagementPending-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let scope = try ICloudSyncScope(accountID: "Owner", libraryID: UUID())
    var snapshot = LibrarySnapshot(); let space = Space(title: "Writing")
    let page = Page(spaceID: space.id, title: "Page")
    snapshot.spaces = [space]; snapshot.pages = [page]
    let receipts = try ICloudOwnerShareReceipts(directory: directory, scope: scope)
    #expect(try receipts.managementOperation(for: .page(page.id), snapshot: snapshot) == nil)
    let plan = try ICloudShareRecordPlan(scope: .page(page.id), snapshot: snapshot)
    let pending = try receipts.begin(plan: plan, shareName: "pending-share")
    snapshot.comments.append(Comment(pageID: page.id, blockID: nil, body: "Later", author: "Owner"))
    #expect(try receipts.managementOperation(for: .page(page.id), snapshot: snapshot) == nil)
    let changedPlan = try ICloudShareRecordPlan(scope: .page(page.id), snapshot: snapshot)
    #expect(throws: ICloudShareOwnerError.changedManifest) { try receipts.operation(for: changedPlan) }
    #expect(try receipts.operation(for: plan) == pending)
    try receipts.confirm(pending)
    #expect(try receipts.managementOperation(for: .page(page.id), snapshot: snapshot)?.confirmed == true)
    #expect(try ICloudOwnerShareReceipts(directory: directory, scope: ICloudSyncScope(accountID: "Other", libraryID: scope.libraryID))
        .managementOperation(for: .page(page.id), snapshot: snapshot) == nil)
    #expect(try ICloudOwnerShareReceipts(directory: directory, scope: ICloudSyncScope(accountID: scope.accountID, libraryID: UUID()))
        .managementOperation(for: .page(page.id), snapshot: snapshot) == nil)
    snapshot.pages[0].trashedAt = Date()
    #expect(throws: LibraryError.trashedPage) { try receipts.managementOperation(for: .page(page.id), snapshot: snapshot) }
    snapshot.pages.removeAll()
    #expect(throws: LibraryError.missingPage) { try receipts.managementOperation(for: .page(page.id), snapshot: snapshot) }
    snapshot.spaces.removeAll()
    #expect(throws: LibraryError.missingSpace) { try receipts.managementOperation(for: .space(space.id), snapshot: snapshot) }
}

@MainActor private final class ManagementReaderFixture {
    let scope = try! ICloudSyncScope(accountID: "e\u{301}", libraryID: UUID())
    let page = Page(spaceID: UUID(), title: "Shared")
    var root: CKRecord {
        let value = CKRecord(recordType: "ScriptumItemV1", recordID: rootID)
        value["libraryID"] = scope.libraryID.uuidString.lowercased() as CKRecordValue
        value["kind"] = "page" as CKRecordValue
        value["uuid"] = page.id.uuidString.lowercased() as CKRecordValue
        value["operation"] = "upsert" as CKRecordValue
        return value
    }
    var zone: CKRecordZone.ID { .init(zoneName: "Scriptum-" + scope.libraryID.uuidString.lowercased(), ownerName: CKCurrentUserDefaultName) }
    var rootID: CKRecord.ID { .init(recordName: "page:" + page.id.uuidString.lowercased(), zoneID: zone) }
    var shareID: CKRecord.ID { .init(recordName: "cloudkit.share.confirmed", zoneID: zone) }
    var operation: ICloudOwnerShareReceipts.Operation {
        .init(id: UUID(), rootName: rootID.recordName, shareName: shareID.recordName,
              manifestDigest: String(repeating: "0", count: 64), confirmed: true)
    }
    var calls: [String] = []
    var current = true
    var afterRead: ((Int) -> Void)?
    func didRead(_ call: String) { calls.append(call); afterRead?(calls.count) }
    func reader() -> ICloudOwnerShareManagementReader {
        .init(account: {
            self.didRead("account")
            return self.scope.accountID
        }, root: { id in
            #expect(id == self.rootID); self.didRead("root")
            return .init(record: self.root, shareID: self.shareID)
        }, share: { id in
            #expect(id == self.shareID); self.didRead("share")
            let record = CKShare(rootRecord: self.root, shareID: self.shareID)
            record.publicPermission = .none
            record[CKShare.SystemFieldKey.title] = "Read \(self.calls.count)" as CKRecordValue
            return .init(record: record, isOwner: true)
        })
    }
}

@Test @MainActor func ownerShareManagementReadsFreshNativeIdentityAndReturnsLatestShare() async throws {
    let f = ManagementReaderFixture()
    let result = try await f.reader().open(operation: f.operation, scope: f.scope) { f.current }
    #expect(result.recordID == f.shareID)
    #expect(result[CKShare.SystemFieldKey.title] as? String == "Read 5")
    #expect(f.calls == ["account", "root", "share", "root", "share", "account"])
}

@Test(arguments: 0...6) @MainActor
func ownerShareManagementRejectsSessionChangeAfterEveryRead(boundary: Int) async throws {
    let f = ManagementReaderFixture()
    if boundary == 0 { f.current = false }
    f.afterRead = { if $0 == boundary { f.current = false } }
    await #expect(throws: ICloudShareOwnerError.accountChanged) {
        try await f.reader().open(operation: f.operation, scope: f.scope) { f.current }
    }
    #expect(f.calls.count == boundary)
}

@Test(arguments: 0...6) @MainActor
func ownerShareManagementCancellationStopsAfterEveryRead(boundary: Int) async throws {
    let f = ManagementReaderFixture()
    f.afterRead = { if $0 == boundary { withUnsafeCurrentTask { $0?.cancel() } } }
    let operation = f.operation
    let task = Task {
        if boundary == 0 { withUnsafeCurrentTask { $0?.cancel() } }
        return try await f.reader().open(operation: operation, scope: f.scope) { f.current }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(f.calls.count == boundary)
}

@Test(arguments: [1, 2]) @MainActor
func ownerShareManagementRejectsByteDifferentAccountAtEitherBoundary(lookup: Int) async throws {
    let f = ManagementReaderFixture(), native = f.reader()
    var calls = 0
    let reader = ICloudOwnerShareManagementReader(account: {
        calls += 1
        return calls == lookup ? "é" : f.scope.accountID
    }, root: native.root, share: native.share)
    await #expect(throws: ICloudShareOwnerError.accountChanged) {
        try await reader.open(operation: f.operation, scope: f.scope) { true }
    }
    #expect(calls == lookup)
}

@Test(arguments: ["rootID", "rootZone", "type", "library", "kind", "uuid", "tombstone", "parent", "rootShare", "shareID", "shareZone", "owner", "public"])
@MainActor func ownerShareManagementRejectsChangedNativeIdentityOnRefresh(mismatch: String) async throws {
    let f = ManagementReaderFixture(), native = f.reader()
    var roots = 0, shares = 0
    let otherZone = CKRecordZone.ID(zoneName: "Other", ownerName: CKCurrentUserDefaultName)
    let reader = ICloudOwnerShareManagementReader(account: native.account, root: { id in
        roots += 1
        if roots == 1 { return try await native.root(id) }
        var record = f.root
        var shareID: CKRecord.ID? = f.shareID
        switch mismatch {
        case "rootID": record = CKRecord(recordType: "ScriptumItemV1", recordID: .init(recordName: "other", zoneID: f.zone))
        case "rootZone": record = CKRecord(recordType: "ScriptumItemV1", recordID: .init(recordName: id.recordName, zoneID: otherZone))
        case "type": record = CKRecord(recordType: "Other", recordID: id)
        case "library": record["libraryID"] = UUID().uuidString.lowercased() as CKRecordValue
        case "kind": record["kind"] = "comment" as CKRecordValue
        case "uuid": record["uuid"] = UUID().uuidString.lowercased() as CKRecordValue
        case "tombstone": record["operation"] = "tombstone" as CKRecordValue
        case "parent": record.parent = .init(recordID: .init(recordName: "other", zoneID: f.zone), action: .none)
        case "rootShare": shareID = .init(recordName: "replaced-share", zoneID: f.zone)
        default: break
        }
        return .init(record: record, shareID: shareID)
    }, share: { id in
        shares += 1
        if shares == 1 { return try await native.share(id) }
        let actualID: CKRecord.ID
        if mismatch == "shareID" { actualID = .init(recordName: "replaced-share", zoneID: f.zone) }
        else if mismatch == "shareZone" { actualID = .init(recordName: id.recordName, zoneID: otherZone) }
        else { actualID = id }
        let root = CKRecord(recordType: "ScriptumItemV1", recordID: .init(recordName: f.rootID.recordName, zoneID: actualID.zoneID))
        let record = CKShare(rootRecord: root, shareID: actualID)
        record.publicPermission = mismatch == "public" ? .readOnly : .none
        return .init(record: record, isOwner: mismatch != "owner")
    })
    await #expect(throws: ICloudShareOwnerError.invalidReceipt) {
        try await reader.open(operation: f.operation, scope: f.scope) { true }
    }
    #expect(roots == 2)
}

@Test(arguments: [CKError.Code.unknownItem, .permissionFailure, .networkFailure]) @MainActor
func ownerShareManagementPropagatesMissingOrDeniedShareWithoutCreatingReplacement(code: CKError.Code) async throws {
    let f = ManagementReaderFixture(), native = f.reader()
    let reader = ICloudOwnerShareManagementReader(account: native.account, root: native.root, share: { _ in throw CKError(code) })
    do { _ = try await reader.open(operation: f.operation, scope: f.scope) { true }; Issue.record("Failed share reopened") }
    catch let error as CKError { #expect(error.code == code) }
    #expect(f.calls == ["account", "root"])
}

@Test @MainActor func ownerShareManagementRejectsPendingReceiptBeforeReadingCloudKit() async throws {
    let f = ManagementReaderFixture()
    var operation = f.operation; operation.confirmed = false
    await #expect(throws: ICloudShareOwnerError.invalidReceipt) {
        try await f.reader().open(operation: operation, scope: f.scope) { true }
    }
    #expect(f.calls.isEmpty)
}

@Test @MainActor func ownerShareManagementRejectsRootTrashedWhileFetchingNativeShare() async throws {
    let f = ManagementReaderFixture()
    var snapshot = LibrarySnapshot(); snapshot.pages = [f.page]
    f.afterRead = { if $0 == 3 { snapshot.pages[0].trashedAt = Date() } }
    await #expect(throws: ICloudShareOwnerError.accountChanged) {
        try await f.reader().open(operation: f.operation, scope: f.scope) {
            (try? ICloudOwnerShareReceipts.managementRoot(for: .page(f.page.id), snapshot: snapshot)) == f.rootID.recordName
        }
    }
    #expect(f.calls.count == 3)
}

@Test(arguments: ["cancel", "session", "transport", "receipt"])
@MainActor func ownerShareManagementFinalPresentationRejectsChangesDuringLastActorHop(change: String) async throws {
    var current = true, receiptValid = true, reads = 0
    let task = Task {
        try await ICloudOwnerShareManagementReader.confirmPresentation(transportIsActive: {
            reads += 1
            if change == "cancel" { withUnsafeCurrentTask { $0?.cancel() } }
            if change == "session" { current = false }
            if change == "receipt" { receiptValid = false }
            return change != "transport"
        }, isCurrent: { current && receiptValid })
    }
    if change == "cancel" { await #expect(throws: CancellationError.self) { try await task.value } }
    else { await #expect(throws: ICloudOwnerPresentationError.self) { try await task.value } }
    #expect(reads == 1)
}

@Test @MainActor func ownerShareManagementFinalPresentationAcceptsCurrentTransportAndReceipt() async throws {
    var checks = 0
    try await ICloudOwnerShareManagementReader.confirmPresentation(transportIsActive: { true }, isCurrent: {
        checks += 1; return true
    })
    #expect(checks == 2)
}

@Test(arguments: [false, true]) @MainActor
func ownerShareManagementOtherWindowDisconnectFencesEvenFailedPersistence(writeFails: Bool) async throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ShareWindowFence-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let f = ManagementReaderFixture()
    let choice = ICloudOwnerConnectionChoice(directory: directory, libraryID: f.scope.libraryID)
    _ = try choice.enable(scope: f.scope, replacing: nil, intent: choice.runtimeRevision)
    let connection = try ICloudOwnerShareConnection(choice: choice, scope: f.scope)
    let peer = ICloudOwnerConnectionChoice(directory: directory, libraryID: f.scope.libraryID, beforeWrite: {
        if writeFails { throw CocoaError(.fileWriteOutOfSpace) }
    })
    f.afterRead = { if $0 == 3 { try? peer.disable(lastKnownScope: f.scope) } }
    await #expect(throws: ICloudShareOwnerError.accountChanged) {
        try await f.reader().open(operation: f.operation, scope: f.scope) { connection.isCurrent }
    }
    #expect(f.calls.count == 3)
    #expect(!connection.isCurrent)
    // An explicit reconnect is a new intent, even with the same account.
    let previous = try choice.load()
    _ = try choice.enable(scope: f.scope, replacing: previous, intent: choice.runtimeRevision)
    #expect(!connection.isCurrent)
    #expect(try ICloudOwnerShareConnection(choice: choice, scope: f.scope).isCurrent)
}

@Test(arguments: ["", String(repeating: "x", count: 257), "invalid\nname"])
@MainActor func ownerShareManagementRejectsInvalidRecordNamesBeforeCloudKitConstruction(name: String) async throws {
    let f = ManagementReaderFixture()
    let operation = ICloudOwnerShareReceipts.Operation(id: UUID(), rootName: f.rootID.recordName,
        shareName: name, manifestDigest: String(repeating: "0", count: 64), confirmed: true)
    await #expect(throws: ICloudShareOwnerError.invalidReceipt) {
        try await f.reader().open(operation: operation, scope: f.scope) { true }
    }
    #expect(f.calls.isEmpty)
}
