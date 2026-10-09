import Foundation
import CloudKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif

enum ICloudShareParticipantError: Error {
    case wrongContainer, unsupportedShare, accountChanged, notAccepted, permissionDenied, invalidRoot
}

/// Native invitation acceptance and authoritative participant access. Receiving
/// document changes still requires a separate durable shared-database sync engine.
@MainActor final class ICloudShareParticipantTransport {
    struct Accepted {
        let share: CKShare
        let root: CKRecord
        let canWrite: Bool
        let participantRecordID: CKRecord.ID
    }
    private let containerIdentifier: String
    private var container: CKContainer { CKContainer(identifier: containerIdentifier) }
    private let accountID: String
    init(containerIdentifier: String, accountID: String) {
        self.containerIdentifier = containerIdentifier
        self.accountID = accountID
    }
    func accept(_ metadata: CKShare.Metadata, isCurrent: () -> Bool) async throws -> Accepted {
        guard metadata.containerIdentifier.utf8.elementsEqual(containerIdentifier.utf8) else {
            throw ICloudShareParticipantError.wrongContainer
        }
        guard let rootID = metadata.hierarchicalRootRecordID,
              rootID.zoneID == metadata.share.recordID.zoneID else { throw ICloudShareParticipantError.unsupportedShare }
        try validateRootIdentity(rootID)
        try await checkAccount(isCurrent: isCurrent)
        _ = try await container.accept(metadata)
        // Acceptance response alone is not proof that the shared database has
        // usable content and a current participant grant.
        return try await load(shareID: metadata.share.recordID, rootID: rootID, isCurrent: isCurrent)
    }
    func load(shareID: CKRecord.ID, rootID: CKRecord.ID,
              isCurrent: () -> Bool) async throws -> Accepted {
        guard shareID.zoneID == rootID.zoneID else { throw ICloudShareParticipantError.invalidRoot }
        try validateRootIdentity(rootID)
        try await checkAccount(isCurrent: isCurrent)
        let database = container.sharedCloudDatabase
        guard let share = try await database.record(for: shareID) as? CKShare,
              let participant = share.currentUserParticipant,
              participant.acceptanceStatus == .accepted else { throw ICloudShareParticipantError.notAccepted }
        guard participant.permission == .readOnly || participant.permission == .readWrite,
              let identity = participant.userIdentity.userRecordID else { throw ICloudShareParticipantError.permissionDenied }
        let root = try await database.record(for: rootID)
        guard root.recordType == "ScriptumItemV1", root.share?.recordID == share.recordID,
              root["operation"] as? String == "upsert" else { throw ICloudShareParticipantError.invalidRoot }
        let parts = rootID.recordName.split(separator: ":")
        guard root["kind"] as? String == String(parts[0]), root["uuid"] as? String == String(parts[1]) else {
            throw ICloudShareParticipantError.invalidRoot
        }
        try await checkAccount(isCurrent: isCurrent)
        return Accepted(share: share, root: root, canWrite: participant.permission == .readWrite, participantRecordID: identity)
    }
    func receive(accepted: Accepted, store: ICloudSharedDocumentStore, imageDirectory: URL,
                 isCurrent: () -> Bool) async throws -> ICloudSharedDocumentContext {
        guard store.identity.accountID.utf8.elementsEqual(accountID.utf8) else { throw ICloudShareParticipantError.accountChanged }
        _ = try await load(shareID: accepted.share.recordID, rootID: accepted.root.recordID, isCurrent: isCurrent)
        return try await ICloudSharedSnapshotReceiver.receive(container: container, accepted: accepted,
            store: store, imageDirectory: imageDirectory) {
                try await self.load(shareID: accepted.share.recordID, rootID: accepted.root.recordID, isCurrent: isCurrent)
            }
    }
    private func validateRootIdentity(_ id: CKRecord.ID) throws {
        let parts = id.recordName.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "page" || parts[0] == "space",
              let uuid = UUID(uuidString: String(parts[1])), uuid.uuidString.lowercased() == parts[1] else {
            throw ICloudShareParticipantError.invalidRoot
        }
    }
    private func checkAccount(isCurrent: () -> Bool) async throws {
        try Task.checkCancellation()
        guard isCurrent(), try await container.accountStatus() == .available,
              try await container.userRecordID().recordName.utf8.elementsEqual(accountID.utf8),
              isCurrent() else { throw ICloudShareParticipantError.accountChanged }
    }
}
