import Foundation
import CloudKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif

enum ICloudShareOwnerError: Error { case accountChanged, capacity, unconfirmedSave }

/// Owner-side creation only. The app must serialize this with its sync engine
/// and retain a local operation receipt before exposing this through the UI.
@MainActor final class ICloudShareOwnerTransport {
    private let containerIdentifier: String
    private var container: CKContainer { CKContainer(identifier: containerIdentifier) }
    private let scope: ICloudSyncScope
    init(containerIdentifier: String, scope: ICloudSyncScope) {
        self.containerIdentifier = containerIdentifier; self.scope = scope
    }
    func create(plan: ICloudShareRecordPlan, title: String,
                isCurrent: () -> Bool) async throws -> CKShare {
        try await checkAccount(isCurrent: isCurrent)
        let database = container.privateCloudDatabase
        let zone = CKRecordZone.ID(zoneName: "Scriptum-" + scope.libraryID.uuidString.lowercased(), ownerName: CKCurrentUserDefaultName)
        var token: CKServerChangeToken?, records: [CKRecord.ID: CKRecord] = [:]
        var more = true
        // Fetch every page, including deletions, before checking descendants.
        // Selected assets are fetched separately to avoid downloading all private
        // manuscript images while inspecting the hierarchy.
        while more {
            try Task.checkCancellation()
            guard isCurrent() else { throw ICloudShareOwnerError.accountChanged }
            let page = try await database.recordZoneChanges(inZoneWith: zone, since: token,
                desiredKeys: ["libraryID", "kind", "uuid", "operation"], resultsLimit: 200)
            for (id, value) in page.modificationResultsByID { records[id] = try value.get().record }
            for deletion in page.deletions { records.removeValue(forKey: deletion.recordID) }
            guard records.count <= 4096 else { throw ICloudShareOwnerError.capacity }
            token = page.changeToken; more = page.moreComing
        }
        for entry in plan.entries {
            try Task.checkCancellation()
            guard isCurrent() else { throw ICloudShareOwnerError.accountChanged }
            let name = entry.source.kind.rawValue + ":" + entry.source.id.uuidString.lowercased()
            let id = CKRecord.ID(recordName: name, zoneID: zone)
            records[id] = try await database.record(for: id)
        }
        try await checkAccount(isCurrent: isCurrent)
        let prepared = try ICloudShareRecordBuilder.prepare(plan: plan, zoneID: zone,
            libraryID: scope.libraryID, zoneRecords: Array(records.values), title: title)
        let saving = prepared.records + [prepared.share]
        // One atomic operation: a rejected or oversized hierarchy must not leave
        // a partly granted share. Server limits propagate rather than truncating.
        let result = try await database.modifyRecords(saving: saving, deleting: [],
            savePolicy: .ifServerRecordUnchanged, atomically: true)
        for record in saving {
            guard let saved = result.saveResults[record.recordID] else { throw ICloudShareOwnerError.unconfirmedSave }
            _ = try saved.get()
        }
        guard let savedShare = try result.saveResults[prepared.share.recordID]?.get() as? CKShare else {
            throw ICloudShareOwnerError.unconfirmedSave
        }
        try await checkAccount(isCurrent: isCurrent)
        return savedShare
    }
    private func checkAccount(isCurrent: () -> Bool) async throws {
        try Task.checkCancellation()
        guard isCurrent(), try await container.accountStatus() == .available,
              try await container.userRecordID().recordName.utf8.elementsEqual(scope.accountID.utf8),
              isCurrent() else { throw ICloudShareOwnerError.accountChanged }
    }
}
