import Foundation
import Testing
@testable import SkriptumCore

@Test @MainActor func privateSharedDraftSurvivesRestartAndCannotEraseNewerText() throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumSharedDraft-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let pageID = UUID(), root = ICloudSyncRecordID(kind: .page, id: UUID())
    let identity = try ICloudSharedStoreIdentity(accountID: "participant", ownerID: "owner", zoneName: "zone", shareName: "share", root: root)
    let store = try ICloudSharedDraftStore(directory: directory, identity: identity)
    let draft = ICloudSharedDraft(id: UUID(), pageID: pageID, baseRevision: UUID(), text: "e\u{301}\r\nUnsaved 🦊")
    try store.save(draft)
    let restarted = try ICloudSharedDraftStore(directory: directory, identity: identity)
    let recovered = try restarted.drafts()
    #expect(recovered.count == 1)
    #expect(recovered.first?.text.utf8.elementsEqual(draft.text.utf8) == true)
    #expect(recovered.first?.baseRevision == draft.baseRevision)
    let newer = ICloudSharedDraft(id: draft.id, pageID: pageID, baseRevision: draft.baseRevision, text: "Newer text")
    try restarted.save(newer)
    #expect(try store.remove(draft.id, matching: draft.text) == false)
    #expect(try store.drafts().first?.text == newer.text)
    let other = try ICloudSharedDraftStore(directory: directory, identity: .init(accountID: "other", ownerID: "owner", zoneName: "zone", shareName: "share", root: root))
    #expect(try other.drafts().isEmpty)
    #expect(try restarted.remove(draft.id, matching: newer.text))
    #expect(try store.drafts().isEmpty)
}

@Test @MainActor func corruptDraftIsRetainedAndLinkedDraftCannotOverwriteItsTarget() throws {
    let directory = URL(fileURLWithPath: "/private/tmp/ScriptumSharedDraftFault-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let identity = try ICloudSharedStoreIdentity(accountID: "participant", ownerID: "owner", zoneName: "zone", shareName: "share", root: .init(kind: .page, id: UUID()))
    let store = try ICloudSharedDraftStore(directory: directory, identity: identity)
    let draft = ICloudSharedDraft(id: UUID(), pageID: UUID(), baseRevision: UUID(), text: "Draft")
    try store.save(draft)
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    let file = try #require(files.first { $0.pathExtension == "json" })
    let corrupt = Data("corrupt draft retained".utf8)
    try corrupt.write(to: file)
    #expect(throws: (any Error).self) { try store.save(draft) }
    #expect(try Data(contentsOf: file) == corrupt)
    try FileManager.default.removeItem(at: file)
    let target = directory.appendingPathComponent("unrelated-file")
    let bytes = Data("Unrelated bytes".utf8); try bytes.write(to: target)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
    #expect(throws: ICloudSharedStoreError.unsafeFile) { try store.save(draft) }
    #expect(throws: ICloudSharedStoreError.unsafeFile) { try store.remove(draft.id, matching: draft.text) }
    #expect(try Data(contentsOf: target) == bytes)
}
