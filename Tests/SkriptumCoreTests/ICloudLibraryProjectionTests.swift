import Foundation
import Testing
@testable import SkriptumCore

@Test @MainActor func iCloudProjectionOnlyQueuesChangedDocumentRecordsWithAncestry() throws {
    var before = LibrarySnapshot()
    let space = Space(title: "Writing"), page = Page(spaceID: UUID(), title: "Unused")
    before.spaces = [space]
    var local = page; local.spaceID = space.id; before.pages = [local]
    #expect(try ICloudLibraryProjection.changes(from: before, to: before).isEmpty)
    var after = before
    after.pages[0].revision = UUID(); after.pages[0].blocks = [Block(markdown: "e\u{301}\r\n🦊")]
    let changes = try ICloudLibraryProjection.changes(from: before, to: after)
    #expect(changes.count == 1)
    let change = try #require(changes.first)
    let payload = try ICloudPagePayload.decode(change.payload, expectedPageID: local.id, expectedRevision: after.pages[0].revision)
    #expect(payload.baseRevision == local.revision)
    #expect(payload.page == after.pages[0])
    var invalid = before; invalid.pages[0].title = "Changed without revision"
    #expect(throws: LibraryError.invalidLibrary) { try ICloudLibraryProjection.changes(from: before, to: invalid) }
}

@Test @MainActor func iCloudProjectionEmitsDeletionAndStableMetadataRevision() throws {
    var before = LibrarySnapshot(); let space = Space(title: "Writing")
    before.spaces = [space]; before.pages = [Page(spaceID: space.id, title: "Page")]
    var after = before; after.spaces[0].title = "Renamed"; after.pages = []
    let first = try ICloudLibraryProjection.changes(from: before, to: after)
    let second = try ICloudLibraryProjection.changes(from: before, to: after)
    #expect(first == second)
    #expect(first.first(where: { $0.recordID.kind == .space }) == second.first(where: { $0.recordID.kind == .space }))
    #expect(first.first(where: { $0.recordID.kind == .page })?.operation == .tombstone)
    #expect(first.first(where: { $0.recordID.kind == .page })?.payload.isEmpty == true)
}
