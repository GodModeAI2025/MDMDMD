import Foundation
import CloudKit
import Testing
@testable import SkriptumWorkspaceModel

@Test @MainActor func participantTransportRejectsForeignHierarchyAndStoppedActivationBeforeAccountAccess() async throws {
    let transport = ICloudShareParticipantTransport(containerIdentifier: "iCloud.com.mobilebox.Skriptum", accountID: "owned-test-account")
    let zone = CKRecordZone.ID(zoneName: "Shared", ownerName: "owner")
    let otherZone = CKRecordZone.ID(zoneName: "Private", ownerName: "other")
    let share = CKRecord.ID(recordName: "share", zoneID: zone)
    let root = CKRecord.ID(recordName: "page:" + UUID().uuidString.lowercased(), zoneID: zone)
    do {
        _ = try await transport.load(shareID: share, rootID: .init(recordName: root.recordName, zoneID: otherZone), isCurrent: { true })
        Issue.record("Cross-zone share accepted")
    } catch { #expect(error as? ICloudShareParticipantError == .invalidRoot) }
    do {
        _ = try await transport.load(shareID: share, rootID: .init(recordName: "image:" + UUID().uuidString.lowercased(), zoneID: zone), isCurrent: { true })
        Issue.record("Image accepted as document-share root")
    } catch { #expect(error as? ICloudShareParticipantError == .invalidRoot) }
    do {
        _ = try await transport.load(shareID: share, rootID: root, isCurrent: { false })
        Issue.record("Stopped activation accepted")
    } catch { #expect(error as? ICloudShareParticipantError == .accountChanged) }
}
