import Foundation
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@Test @MainActor func sharedCatalogRestoresOnlyCurrentAccountAndKeepsDocumentFilesWhenUnlisted() throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumCatalog-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let catalog = try ICloudSharedCatalog(directory: directory.appendingPathComponent("Nested/Shared"))
    let root = ICloudSyncRecordID(kind: .page, id: UUID())
    let a = try ICloudSharedStoreIdentity(accountID: "account-a", ownerID: "owner", zoneName: "zone", shareName: "share", root: root)
    let b = try ICloudSharedStoreIdentity(accountID: "account-b", ownerID: "owner", zoneName: "zone", shareName: "share", root: root)
    try catalog.record(a, title: "First")
    try catalog.record(b, title: "Private other account")
    try catalog.record(a, title: "Updated")
    let reopened = try ICloudSharedCatalog(directory: directory.appendingPathComponent("Nested/Shared"))
    #expect(try reopened.entries(accountID: a.accountID).map(\.titlePreview) == ["Updated"])
    #expect(try reopened.entries(accountID: b.accountID).map(\.titlePreview) == ["Private other account"])
    let preserved = directory.appendingPathComponent("owned-document")
    try Data("Preserved".utf8).write(to: preserved)
    try reopened.remove(a)
    #expect(try reopened.entries(accountID: a.accountID).isEmpty)
    #expect(try Data(contentsOf: preserved) == Data("Preserved".utf8))
    #expect(try reopened.entries(accountID: b.accountID).count == 1)
}
