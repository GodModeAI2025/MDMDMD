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
