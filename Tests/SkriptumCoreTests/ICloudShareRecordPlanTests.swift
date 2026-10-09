import Foundation
import Testing
@testable import SkriptumCore

@Test @MainActor func sharesUsingTheSameImageHaveIndependentAssetParents() throws {
    var snapshot = LibrarySnapshot()
    let space = Space(title: "Writing"); snapshot.spaces = [space]
    let attachment = MediaAttachment(id: UUID(), filename: "image.png", mediaType: "image/png", byteCount: 100, sha256: String(repeating: "a", count: 64))
    var first = Page(spaceID: space.id, title: "First")
    var second = Page(spaceID: space.id, title: "Second")
    let privatePage = Page(spaceID: space.id, title: "Private")
    first.attachments = [attachment]; second.attachments = [attachment]
    snapshot.pages = [first, second, privatePage]
    let a = try ICloudShareRecordPlan(scope: .page(first.id), snapshot: snapshot)
    let b = try ICloudShareRecordPlan(scope: .page(second.id), snapshot: snapshot)
    let imageA = try #require(a.entries.first { $0.isImageAlias })
    let imageB = try #require(b.entries.first { $0.isImageAlias })
    #expect(imageA.source == imageB.source)
    #expect(imageA.recordName != imageB.recordName)
    #expect(imageA.parentRecordName == a.rootRecordName)
    #expect(imageB.parentRecordName == b.rootRecordName)
    #expect(!a.entries.contains { $0.source.id == second.id || $0.source.id == privatePage.id })
    #expect(!b.entries.contains { $0.source.id == first.id || $0.source.id == privatePage.id })
    #expect(a.entries == (try ICloudShareRecordPlan(scope: .page(first.id), snapshot: snapshot)).entries)
    #expect(a.entries.filter { $0.parentRecordName == nil }.count == 1)
}
