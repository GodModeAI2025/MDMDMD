import Foundation
import CloudKit
import CryptoKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif

enum ICloudShareOwnerError: Error { case accountChanged, capacity, unconfirmedSave, changedManifest, invalidReceipt }

/// Owner-side creation and read-only management. The app serializes this with
/// its sync engine; creation receipts fence retries without freezing management.
@MainActor final class ICloudShareOwnerTransport {
    struct Result { let share: CKShare; let records: [CKRecord] }
    private let containerIdentifier: String
    private var container: CKContainer { CKContainer(identifier: containerIdentifier) }
    private let scope: ICloudSyncScope
    init(containerIdentifier: String, scope: ICloudSyncScope) {
        self.containerIdentifier = containerIdentifier; self.scope = scope
    }
    func reopen(_ operation: ICloudOwnerShareReceipts.Operation, isCurrent: () -> Bool) async throws -> CKShare {
        let container = container
        let database = container.privateCloudDatabase
        let reader = ICloudOwnerShareManagementReader(account: {
            try ICloudAccountAvailability.require(try await container.accountStatus())
            return try await container.userRecordID().recordName
        }, root: { id in
            ICloudOwnerShareManagementReader.Root(try await database.record(for: id))
        }, share: { id in
            guard let share = try await database.record(for: id) as? CKShare else { throw ICloudShareOwnerError.invalidReceipt }
            return ICloudOwnerShareManagementReader.Share(share)
        })
        return try await reader.open(operation: operation, scope: scope, isCurrent: isCurrent)
    }
    func create(plan: ICloudShareRecordPlan, title: String, receipts: ICloudOwnerShareReceipts,
                isCurrent: () -> Bool) async throws -> Result {
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
                var selected: [CKRecord] = []
                for entry in plan.entries {
                    try await checkAccount(isCurrent: isCurrent)
                    let fetched = try await database.record(for: .init(recordName: entry.recordName, zoneID: zone))
                    selected.append(fetched); records[fetched.recordID] = fetched
                }
                try await checkAccount(isCurrent: isCurrent)
                guard let refreshedShare = try await database.record(for: shareID) as? CKShare else { throw ICloudShareOwnerError.invalidReceipt }
                try await checkAccount(isCurrent: isCurrent)
                try ICloudShareRecordBuilder.validateSaved(plan: plan, zoneID: zone, libraryID: scope.libraryID,
                    zoneRecords: Array(records.values), share: refreshedShare)
                try receipts.confirm(previous)
                return Result(share: refreshedShare, records: selected)
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
        let saved = try Self.savedResult(saving: saving, shareID: prepared.share.recordID, saveResults: result.saveResults)
        try await checkAccount(isCurrent: isCurrent)
        try receipts.confirm(operation)
        return saved
    }
    static func savedResult(saving: [CKRecord], shareID: CKRecord.ID,
                            saveResults: [CKRecord.ID: Swift.Result<CKRecord, any Error>]) throws -> Result {
        // Atomic saves commonly report batchRequestFailed for the root while
        // another item (often the share) carries the actual rejection. Inspect
        // every result before validation so missing or collateral results never
        // hide that cause. Diagnostics expose only the fixed CloudKit codes.
        var failures: [CKRecord.ID: any Error] = [:]
        for (id, result) in saveResults {
            if case .failure(let error) = result { failures[id] = error }
        }
        guard failures.isEmpty else {
            throw CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: failures])
        }
        let expected = Set(saving.map(\.recordID))
        let shares = saving.compactMap { $0 as? CKShare }
        guard expected.count == saving.count, expected == Set(saveResults.keys),
              shares.count == 1, shares.first?.recordID == shareID else {
            throw ICloudShareOwnerError.unconfirmedSave
        }
        var savedRecords: [CKRecord] = []
        for record in saving {
            guard let saved = saveResults[record.recordID] else { throw ICloudShareOwnerError.unconfirmedSave }
            let receipt = try saved.get()
            guard receipt.recordID == record.recordID, receipt.recordType == record.recordType else { throw ICloudShareOwnerError.unconfirmedSave }
            if !(record is CKShare) { savedRecords.append(receipt) }
        }
        guard let savedShare = try saveResults[shareID]?.get() as? CKShare else {
            throw ICloudShareOwnerError.unconfirmedSave
        }
        return Result(share: savedShare, records: savedRecords)
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
    func managementOperation(for requestedScope: ICloudShareScope, snapshot: LibrarySnapshot) throws -> Operation? {
        let root = try Self.managementRoot(for: requestedScope, snapshot: snapshot)
        // This is an identity lookup, not permission to expand the original
        // hierarchy. Unconfirmed creation still uses the exact manifest below.
        guard let operation = try load().operations.first(where: { $0.rootName == root }), operation.confirmed else { return nil }
        return operation
    }
    static func managementRoot(for requestedScope: ICloudShareScope, snapshot: LibrarySnapshot) throws -> String {
        switch requestedScope {
        case .page(let id):
            guard let page = snapshot.pages.first(where: { $0.id == id }) else { throw LibraryError.missingPage }
            guard page.trashedAt == nil else { throw LibraryError.trashedPage }
            return "page:" + id.uuidString.lowercased()
        case .space(let id):
            guard snapshot.spaces.contains(where: { $0.id == id }) else { throw LibraryError.missingSpace }
            return "space:" + id.uuidString.lowercased()
        }
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

/// Keeps the owner's opt-in bound across windows and asynchronous reads.
@MainActor struct ICloudOwnerShareConnection {
    private let choice: ICloudOwnerConnectionChoice
    private let selection: ICloudOwnerConnectionChoice.Selection
    private let intent: UUID
    init(choice: ICloudOwnerConnectionChoice, scope: ICloudSyncScope) throws {
        guard !choice.isRuntimeDisconnected, let selection = try choice.load(),
              selection.enabled, selection.scope == scope else { throw ICloudOwnerPresentationError.notReady }
        self.choice = choice; self.selection = selection; intent = choice.runtimeRevision
    }
    var isCurrent: Bool {
        !choice.isRuntimeDisconnected && choice.runtimeRevision == intent && (try? choice.load()) == selection
    }
}

/// The only capabilities available while reopening are fresh reads. Read-only
/// native fields have explicit projections so tests never forge CloudKit fields.
@MainActor struct ICloudOwnerShareManagementReader {
    struct Root {
        let record: CKRecord
        let shareID: CKRecord.ID?
        init(_ record: CKRecord) { self.record = record; shareID = record.share?.recordID }
        init(record: CKRecord, shareID: CKRecord.ID?) { self.record = record; self.shareID = shareID }
    }
    struct Share {
        let record: CKShare
        let isOwner: Bool
        init(_ record: CKShare) { self.record = record; isOwner = record.currentUserParticipant?.role == .owner }
        init(record: CKShare, isOwner: Bool) { self.record = record; self.isOwner = isOwner }
    }
    let account: @MainActor () async throws -> String
    let root: @MainActor (CKRecord.ID) async throws -> Root
    let share: @MainActor (CKRecord.ID) async throws -> Share

    /// The last actor hop is also an interruption boundary. Check the caller,
    /// connection and receipt again before handing the native share to the UI.
    static func confirmPresentation(transportIsActive: () async -> Bool,
                                    isCurrent: () throws -> Bool) async throws {
        try Task.checkCancellation()
        guard try isCurrent() else { throw ICloudOwnerPresentationError.notReady }
        let active = await transportIsActive()
        try Task.checkCancellation()
        guard active, try isCurrent() else { throw ICloudOwnerPresentationError.notReady }
    }

    func open(operation: ICloudOwnerShareReceipts.Operation, scope: ICloudSyncScope,
              isCurrent: () -> Bool) async throws -> CKShare {
        func checkCurrent() throws {
            try Task.checkCancellation()
            guard isCurrent() else { throw ICloudShareOwnerError.accountChanged }
        }
        func checkAccount() async throws {
            try checkCurrent()
            let current = try await account()
            try checkCurrent()
            guard current.utf8.elementsEqual(scope.accountID.utf8) else { throw ICloudShareOwnerError.accountChanged }
        }
        let parts = operation.rootName.split(separator: ":", omittingEmptySubsequences: false)
        guard operation.confirmed, parts.count == 2, parts[0] == "page" || parts[0] == "space",
              let id = UUID(uuidString: String(parts[1])), id.uuidString.lowercased() == parts[1],
              !operation.shareName.isEmpty, operation.shareName.utf8.count <= 256,
              operation.shareName.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw ICloudShareOwnerError.invalidReceipt
        }
        let zone = CKRecordZone.ID(zoneName: "Scriptum-" + scope.libraryID.uuidString.lowercased(), ownerName: CKCurrentUserDefaultName)
        let rootID = CKRecord.ID(recordName: operation.rootName, zoneID: zone)
        let shareID = CKRecord.ID(recordName: operation.shareName, zoneID: zone)
        func validateRoot(_ value: Root) throws {
            let record = value.record
            guard record.recordID == rootID, record.recordType == "ScriptumItemV1",
                  record["libraryID"] as? String == scope.libraryID.uuidString.lowercased(),
                  record["kind"] as? String == String(parts[0]), record["uuid"] as? String == String(parts[1]),
                  record["operation"] as? String == "upsert", record.parent == nil,
                  value.shareID == shareID else { throw ICloudShareOwnerError.invalidReceipt }
        }
        func validateShare(_ value: Share) throws {
            guard value.record.recordID == shareID, value.isOwner,
                  value.record.publicPermission == .none else { throw ICloudShareOwnerError.invalidReceipt }
        }
        try await checkAccount()
        // Refresh both links twice. A revoked/replaced root or changed owner
        // must not present a previously fetched sharing controller.
        var currentShare: CKShare?
        for _ in 0..<2 {
            let currentRoot = try await root(rootID)
            try checkCurrent(); try validateRoot(currentRoot)
            let fetchedShare = try await share(shareID)
            try checkCurrent(); try validateShare(fetchedShare)
            currentShare = fetchedShare.record
        }
        try await checkAccount()
        guard let currentShare else { throw ICloudShareOwnerError.invalidReceipt }
        return currentShare
    }
}
