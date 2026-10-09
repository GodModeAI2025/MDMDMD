import Foundation
import CloudKit
import CryptoKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif

enum ICloudShareOwnerError: Error { case accountChanged, capacity, unconfirmedSave, changedManifest, invalidReceipt }

/// Owner-side creation only. The app must serialize this with its sync engine
/// before exposing this through the UI. Receipt persistence fences retries.
@MainActor final class ICloudShareOwnerTransport {
    private let containerIdentifier: String
    private var container: CKContainer { CKContainer(identifier: containerIdentifier) }
    private let scope: ICloudSyncScope
    init(containerIdentifier: String, scope: ICloudSyncScope) {
        self.containerIdentifier = containerIdentifier; self.scope = scope
    }
    func create(plan: ICloudShareRecordPlan, title: String, receipts: ICloudOwnerShareReceipts,
                isCurrent: () -> Bool) async throws -> CKShare {
        guard receipts.scope == scope else { throw ICloudShareOwnerError.invalidReceipt }
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
                desiredKeys: ["libraryID", "kind", "uuid", "operation", "sourceRecordName"], resultsLimit: 200)
            for (id, value) in page.modificationResultsByID { records[id] = try value.get().record }
            for deletion in page.deletions { records.removeValue(forKey: deletion.recordID) }
            guard records.count <= 4096 else { throw ICloudShareOwnerError.capacity }
            token = page.changeToken; more = page.moreComing
        }
        let previous = try receipts.operation(for: plan)
        if let previous {
            let shareID = CKRecord.ID(recordName: previous.shareName, zoneID: zone)
            do {
                guard let share = try await database.record(for: shareID) as? CKShare else { throw ICloudShareOwnerError.invalidReceipt }
                try await checkAccount(isCurrent: isCurrent)
                try ICloudShareRecordBuilder.validateSaved(plan: plan, zoneID: zone, libraryID: scope.libraryID,
                    zoneRecords: Array(records.values), share: share)
                try receipts.confirm(previous)
                return share
            } catch let error as CKError where error.code == .unknownItem {
                // The original atomic save did not leave its share. Reuse its
                // exact record ID; the server's optimistic policy fences races.
                // A local confirmed receipt never becomes a new share silently.
                guard !previous.confirmed else { throw ICloudShareOwnerError.unconfirmedSave }
            }
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
            libraryID: scope.libraryID, zoneRecords: Array(records.values), title: title,
            shareID: previous.map { CKRecord.ID(recordName: $0.shareName, zoneID: zone) })
        let operation = try receipts.begin(plan: plan, shareName: prepared.share.recordID.recordName)
        try await checkAccount(isCurrent: isCurrent)
        let saving = prepared.records + [prepared.share]
        // One atomic operation: a rejected or oversized hierarchy must not leave
        // a partly granted share. Server limits propagate rather than truncating.
        let result = try await database.modifyRecords(saving: saving, deleting: [],
            savePolicy: .ifServerRecordUnchanged, atomically: true)
        for record in saving {
            guard let saved = result.saveResults[record.recordID] else { throw ICloudShareOwnerError.unconfirmedSave }
            let receipt = try saved.get()
            guard receipt.recordID == record.recordID, receipt.recordType == record.recordType else { throw ICloudShareOwnerError.unconfirmedSave }
        }
        guard let savedShare = try result.saveResults[prepared.share.recordID]?.get() as? CKShare else {
            throw ICloudShareOwnerError.unconfirmedSave
        }
        try await checkAccount(isCurrent: isCurrent)
        try receipts.confirm(operation)
        return savedShare
    }
    private func checkAccount(isCurrent: () -> Bool) async throws {
        try Task.checkCancellation()
        guard isCurrent(), try await container.accountStatus() == .available,
              try await container.userRecordID().recordName.utf8.elementsEqual(scope.accountID.utf8),
              isCurrent() else { throw ICloudShareOwnerError.accountChanged }
    }
}

/// Metadata-only owner operation log. It stores no invitation URLs or grants;
/// recovery must fetch and validate native server records before presentation.
@MainActor final class ICloudOwnerShareReceipts {
    struct Operation: Codable, Equatable {
        let id: UUID, rootName: String, shareName: String, manifestDigest: String
        var confirmed: Bool
    }
    private struct Snapshot: Codable { let scope: ICloudSyncScope; var schemaVersion = 1; var operations: [Operation] = [] }
    let scope: ICloudSyncScope
    private let files: ICloudSyncEngine.Files
    init(directory: URL, scope: ICloudSyncScope) throws {
        self.scope = try ICloudSyncScope(accountID: scope.accountID, libraryID: scope.libraryID)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(scope)
        let hash = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
        files = try ICloudSyncEngine.Files(directory: directory, name: "owner-shares-" + hash + ".json", createParents: true)
    }
    func operation(for plan: ICloudShareRecordPlan) throws -> Operation? {
        guard let saved = try load().operations.first(where: { $0.rootName == plan.rootRecordName }) else { return nil }
        guard saved.manifestDigest == Self.digest(plan) else { throw ICloudShareOwnerError.changedManifest }
        return saved
    }
    func begin(plan: ICloudShareRecordPlan, shareName: String) throws -> Operation {
        if let saved = try operation(for: plan) {
            guard saved.shareName.utf8.elementsEqual(shareName.utf8) else { throw ICloudShareOwnerError.invalidReceipt }
            return saved
        }
        var snapshot = try load()
        let operation = Operation(id: UUID(), rootName: plan.rootRecordName, shareName: shareName,
            manifestDigest: Self.digest(plan), confirmed: false)
        snapshot.operations.append(operation)
        try persist(snapshot)
        return operation
    }
    func confirm(_ operation: Operation) throws {
        var snapshot = try load()
        guard let index = snapshot.operations.firstIndex(where: { $0.id == operation.id }),
              snapshot.operations[index].rootName == operation.rootName,
              snapshot.operations[index].shareName.utf8.elementsEqual(operation.shareName.utf8),
              snapshot.operations[index].manifestDigest == operation.manifestDigest else { throw ICloudShareOwnerError.invalidReceipt }
        snapshot.operations[index].confirmed = true; try persist(snapshot)
    }
    private func load() throws -> Snapshot {
        guard let data = try files.read() else { return Snapshot(scope: scope) }
        let value = try JSONDecoder().decode(Snapshot.self, from: data); try validate(value); return value
    }
    private func persist(_ value: Snapshot) throws {
        try validate(value)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try files.write(encoder.encode(value))
    }
    private func validate(_ value: Snapshot) throws {
        guard value.schemaVersion == 1, value.scope == scope, value.operations.count <= 4096,
              Set(value.operations.map(\.rootName)).count == value.operations.count,
              Set(value.operations.map(\.id)).count == value.operations.count,
              Set(value.operations.map(\.shareName)).count == value.operations.count else { throw ICloudShareOwnerError.invalidReceipt }
        for operation in value.operations {
            let root = operation.rootName.split(separator: ":", omittingEmptySubsequences: false)
            guard root.count == 2, root[0] == "page" || root[0] == "space",
                  let id = UUID(uuidString: String(root[1])), id.uuidString.lowercased() == root[1],
                  !operation.shareName.isEmpty, operation.shareName.utf8.count <= 256,
                  operation.shareName.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
                  operation.manifestDigest.utf8.count == 64,
                  operation.manifestDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw ICloudShareOwnerError.invalidReceipt }
        }
    }
    private static func digest(_ plan: ICloudShareRecordPlan) -> String {
        var bytes = Data()
        func append(_ value: String) { bytes.append(contentsOf: String(value.utf8.count).utf8); bytes.append(0); bytes.append(contentsOf: value.utf8) }
        append(plan.rootRecordName)
        for entry in plan.entries.sorted(by: { $0.recordName < $1.recordName }) {
            append(entry.recordName); append(entry.source.kind.rawValue); append(entry.source.id.uuidString.lowercased())
            append(entry.parentRecordName ?? ""); bytes.append(entry.isImageAlias ? 1 : 0)
        }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
