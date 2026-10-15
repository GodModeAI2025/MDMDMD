import Foundation
import CloudKit
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

private struct ShareSaveFixture {
    let root: CKRecord
    let child: CKRecord
    let share: CKShare
    init() {
        let zone = CKRecordZone.ID(zoneName: "Private fixture", ownerName: CKCurrentUserDefaultName)
        root = CKRecord(recordType: "ScriptumItemV1", recordID: .init(recordName: "private-root", zoneID: zone))
        child = CKRecord(recordType: "ScriptumItemV1", recordID: .init(recordName: "private-child", zoneID: zone))
        child.parent = .init(recordID: root.recordID, action: .none)
        share = CKShare(rootRecord: root)
        share.publicPermission = .none
    }
    var saving: [CKRecord] { [root, child, share] }
    var successes: [CKRecord.ID: Result<CKRecord, any Error>] {
        Dictionary(uniqueKeysWithValues: saving.map { ($0.recordID, .success($0)) })
    }
}

@Test(arguments: [CKError.Code.invalidArguments, .serverRecordChanged, .serverRejectedRequest, .alreadyShared], [false, true])
@MainActor func shareSaveReportsActualFailureInsteadOfEarlierBatch22(code: CKError.Code, reversed: Bool) throws {
    let fixture = ShareSaveFixture()
    let privateMessage = "private-document /private/account/identifier"
    let failures: [CKRecord.ID: Result<CKRecord, any Error>] = [
        fixture.root.recordID: .failure(CKError(.batchRequestFailed)),
        fixture.child.recordID: .failure(CKError(.batchRequestFailed)),
        fixture.share.recordID: .failure(CKError(code, userInfo: [NSLocalizedDescriptionKey: privateMessage]))
    ]
    do {
        _ = try ICloudShareOwnerTransport.savedResult(saving: reversed ? Array(fixture.saving.reversed()) : fixture.saving,
            shareID: fixture.share.recordID, saveResults: failures)
        Issue.record("Failed atomic save was accepted")
    } catch {
        let diagnostic = ICloudFailureDiagnostic.describe(error)
        #expect(diagnostic.code == "CloudKit.2[\(code.rawValue),22]" || diagnostic.code == "CloudKit.2[22,\(code.rawValue)]")
        #expect(diagnostic.message == ICloudFailureDiagnostic.describe(CKError(code)).message)
        #expect(!diagnostic.message.contains(privateMessage))
        #expect(!diagnostic.code.contains(fixture.root.recordID.recordName))
        #expect(!diagnostic.code.contains(fixture.share.recordID.recordName))
    }
}

@Test @MainActor func shareSaveRetainsActualFailureEvenWhenAnotherResultIsMissing() throws {
    let fixture = ShareSaveFixture()
    let failures: [CKRecord.ID: Result<CKRecord, any Error>] = [fixture.share.recordID: .failure(CKError(.invalidArguments))]
    do {
        _ = try ICloudShareOwnerTransport.savedResult(saving: fixture.saving, shareID: fixture.share.recordID, saveResults: failures)
        Issue.record("Incomplete failed save was accepted")
    } catch {
        #expect(ICloudFailureDiagnostic.describe(error).code == "CloudKit.2[12]")
    }
}

@Test @MainActor func shareSaveNestedFailureRemainsActionableWithoutExposingRecordData() throws {
    let fixture = ShareSaveFixture(), privateKey = "private record data"
    var results = fixture.successes
    results[fixture.root.recordID] = .failure(CKError(.batchRequestFailed))
    results[fixture.share.recordID] = .failure(CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey:
        [privateKey: CKError(.invalidArguments, userInfo: [NSLocalizedDescriptionKey: privateKey])]]))
    do {
        _ = try ICloudShareOwnerTransport.savedResult(saving: fixture.saving, shareID: fixture.share.recordID, saveResults: results)
        Issue.record("Nested failure was accepted")
    } catch {
        let diagnostic = ICloudFailureDiagnostic.describe(error)
        #expect(diagnostic.code == "CloudKit.2[12,22]")
        #expect(diagnostic.message == ICloudFailureDiagnostic.describe(CKError(.invalidArguments)).message)
        #expect(!diagnostic.message.contains(privateKey))
    }
}

@Test @MainActor func shareSaveWithOnlyCollateralErrorsDoesNotInventCause() throws {
    let fixture = ShareSaveFixture()
    let failures: [CKRecord.ID: Result<CKRecord, any Error>] = Dictionary(uniqueKeysWithValues:
        fixture.saving.map { ($0.recordID, .failure(CKError(.batchRequestFailed))) })
    do {
        _ = try ICloudShareOwnerTransport.savedResult(saving: fixture.saving, shareID: fixture.share.recordID, saveResults: failures)
        Issue.record("Failed batch was accepted")
    } catch {
        let diagnostic = ICloudFailureDiagnostic.describe(error)
        #expect(diagnostic.code == "CloudKit.2[22]")
        #expect(!diagnostic.message.contains("App-Einrichtung"))
        #expect(!diagnostic.message.contains("Anmeldung"))
    }
}

@Test(arguments: ["missing", "extra", "wrong-id", "wrong-zone", "wrong-type", "duplicate-request", "missing-share", "wrong-share", "extra-share", "empty"])
@MainActor func shareSaveRejectsIncompleteOrMismatchedResults(kind: String) throws {
    let fixture = ShareSaveFixture()
    var saving = fixture.saving, results = fixture.successes, shareID = fixture.share.recordID
    switch kind {
    case "missing": results.removeValue(forKey: fixture.root.recordID)
    case "extra":
        let extra = CKRecord(recordType: "ScriptumItemV1")
        results[extra.recordID] = .success(extra)
    case "wrong-id": results[fixture.root.recordID] = .success(fixture.child)
    case "wrong-zone": results[fixture.root.recordID] = .success(CKRecord(recordType: fixture.root.recordType,
        recordID: .init(recordName: fixture.root.recordID.recordName, zoneID: .init(zoneName: "Other", ownerName: CKCurrentUserDefaultName))))
    case "wrong-type": results[fixture.root.recordID] = .success(CKRecord(recordType: "OtherType", recordID: fixture.root.recordID))
    case "duplicate-request": saving.append(fixture.root)
    case "missing-share": saving.removeLast(); results.removeValue(forKey: fixture.share.recordID)
    case "extra-share":
        let extra = CKShare(rootRecord: fixture.child)
        saving.append(extra); results[extra.recordID] = .success(extra)
    case "empty": saving = []; results = [:]
    default: shareID = fixture.root.recordID
    }
    #expect(throws: ICloudShareOwnerError.unconfirmedSave) {
        try ICloudShareOwnerTransport.savedResult(saving: saving, shareID: shareID, saveResults: results)
    }
}

@Test @MainActor func shareSavePreservesNonCloudFailureWithoutExposingItsDescription() throws {
    let fixture = ShareSaveFixture(), secret = "private-record-path"
    var results = fixture.successes
    results[fixture.child.recordID] = .failure(NSError(domain: secret, code: 987, userInfo: [NSLocalizedDescriptionKey: secret]))
    do {
        _ = try ICloudShareOwnerTransport.savedResult(saving: fixture.saving, shareID: fixture.share.recordID, saveResults: results)
        Issue.record("Non-CloudKit failure was accepted")
    } catch {
        let cloud = try #require(error as? CKError)
        #expect(cloud.code == .partialFailure)
        #expect(cloud.partialErrorsByItemID?[fixture.child.recordID] != nil)
        let diagnostic = ICloudFailureDiagnostic.describe(error)
        #expect(!diagnostic.code.contains(secret) && !diagnostic.message.contains(secret))
    }
}

@Test @MainActor func shareSaveReturnsOnlyFullyConfirmedRecordsInRequestedOrder() throws {
    let fixture = ShareSaveFixture()
    let saved = try ICloudShareOwnerTransport.savedResult(saving: fixture.saving, shareID: fixture.share.recordID,
        saveResults: fixture.successes)
    #expect(saved.records.map(\.recordID) == [fixture.root.recordID, fixture.child.recordID])
    #expect(saved.share === fixture.share)
    #expect(saved.share.publicPermission == .none)
    #expect(saved.records[1].parent?.recordID == saved.records[0].recordID)
}

@Test @MainActor func shareSaveFailureLeavesCreationReceiptUnconfirmedAcrossRestart() throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumShareSaveFailure-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let scope = try ICloudSyncScope(accountID: "Test owner", libraryID: UUID())
    var snapshot = LibrarySnapshot(); let space = Space(title: "Writing")
    let page = Page(spaceID: space.id, title: "My page")
    snapshot.spaces = [space]; snapshot.pages = [page]
    let plan = try ICloudShareRecordPlan(scope: .page(page.id), snapshot: snapshot)
    let receipts = try ICloudOwnerShareReceipts(directory: directory, scope: scope)
    let fixture = ShareSaveFixture()
    let operation = try receipts.begin(plan: plan, shareName: fixture.share.recordID.recordName)
    var results = fixture.successes
    results[fixture.root.recordID] = .failure(CKError(.batchRequestFailed))
    results[fixture.share.recordID] = .failure(CKError(.invalidArguments))
    do {
        _ = try ICloudShareOwnerTransport.savedResult(saving: fixture.saving, shareID: fixture.share.recordID, saveResults: results)
        try receipts.confirm(operation)
        Issue.record("A failed share was confirmed")
    } catch {
        #expect(ICloudFailureDiagnostic.describe(error).code == "CloudKit.2[12,22]")
    }
    let reopened = try ICloudOwnerShareReceipts(directory: directory, scope: scope)
    let persisted = try reopened.operation(for: plan)
    #expect(persisted == operation)
    #expect(persisted?.confirmed == false)
}

@Test(arguments: [CKError.Code.serverRecordChanged, .permissionFailure]) @MainActor
func shareMembershipSaveIncludesDeletionCauseInAtomicFailure(code: CKError.Code) throws {
    let fixture = ShareSaveFixture()
    let deleting = CKRecord.ID(recordName: "obsolete-alias", zoneID: fixture.root.recordID.zoneID)
    let failures: [CKRecord.ID: Result<CKRecord, any Error>] = Dictionary(uniqueKeysWithValues:
        fixture.saving.map { ($0.recordID, .failure(CKError(.batchRequestFailed))) })
    do {
        _ = try ICloudShareOwnerTransport.savedResult(saving: fixture.saving, shareID: fixture.share.recordID,
            saveResults: failures, deleting: [deleting], deleteResults: [deleting: .failure(CKError(code))])
        Issue.record("Deletion failure accepted")
    } catch {
        #expect(ICloudFailureDiagnostic.describe(error).message == ICloudFailureDiagnostic.describe(CKError(code)).message)
    }
}

@Test(arguments: ["missing", "extra", "duplicate", "overlap", "valid"]) @MainActor
func shareMembershipSaveRequiresExactDeletionReceipts(scenario: String) throws {
    let fixture = ShareSaveFixture()
    let deleting = CKRecord.ID(recordName: "obsolete-alias", zoneID: fixture.root.recordID.zoneID)
    let ids = scenario == "duplicate" ? [deleting, deleting] : scenario == "overlap" ? [fixture.root.recordID] : [deleting]
    var results: [CKRecord.ID: Result<Void, any Error>] = scenario == "missing" ? [:] : [ids[0]: .success(())]
    if scenario == "extra" { results[CKRecord.ID(recordName: "unexpected", zoneID: deleting.zoneID)] = .success(()) }
    if scenario == "valid" {
        let result = try ICloudShareOwnerTransport.savedResult(saving: fixture.saving, shareID: fixture.share.recordID,
            saveResults: fixture.successes, deleting: ids, deleteResults: results)
        #expect(result.records.count == 2)
    } else {
        #expect(throws: ICloudShareOwnerError.self) {
            try ICloudShareOwnerTransport.savedResult(saving: fixture.saving, shareID: fixture.share.recordID,
                saveResults: fixture.successes, deleting: ids, deleteResults: results)
        }
    }
}

@Test @MainActor func shareMembershipSaveRejectsUnconfirmedNativeParent() throws {
    let fixture = ShareSaveFixture()
    var results = fixture.successes
    let changed = try #require(fixture.child.copy() as? CKRecord); changed.parent = nil
    results[changed.recordID] = .success(changed)
    #expect(throws: ICloudShareOwnerError.self) {
        try ICloudShareOwnerTransport.savedResult(saving: fixture.saving, shareID: fixture.share.recordID, saveResults: results)
    }
}
