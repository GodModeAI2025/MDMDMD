import Foundation
import Testing
@testable import SkriptumCore

@Test @MainActor func crossSpaceHierarchyCannotExpandTheShareScope() throws {
    var snapshot = LibrarySnapshot(); let a = Space(title: "Shared"), b = Space(title: "Private")
    snapshot.spaces = [a, b]
    let root = Page(spaceID: a.id, title: "Shared")
    let child = Page(spaceID: b.id, parentID: root.id, title: "Foreign space")
    snapshot.pages = [root, child]
    #expect(throws: LibraryError.invalidLibrary) { try ICloudShareManifest(scope: .page(root.id), snapshot: snapshot) }
    #expect(throws: LibraryError.invalidLibrary) { try ICloudShareManifest(scope: .space(b.id), snapshot: snapshot) }
}

@Test @MainActor func pageShareContainsRepliesAndDescendantsWithoutUnrelatedPages() throws {
    var snapshot = LibrarySnapshot(); let space = Space(title: "Writing")
    snapshot.spaces = [space]
    let root = Page(spaceID: space.id, title: "Shared")
    let child = Page(spaceID: space.id, parentID: root.id, title: "Child")
    let privatePage = Page(spaceID: space.id, title: "Private")
    snapshot.pages = [privatePage, child, root]
    let comment = Comment(pageID: child.id, blockID: nil, body: "Discussion", author: "A")
    var reply = Comment(pageID: child.id, blockID: nil, body: "Answer", author: "B"); reply.parentCommentID = comment.id
    snapshot.comments = [comment, reply, Comment(pageID: privatePage.id, blockID: nil, body: "Private", author: "A")]
    let manifest = try ICloudShareManifest(scope: .page(root.id), snapshot: snapshot)
    #expect(manifest.pages == [root.id, child.id])
    #expect(manifest.comments == [comment.id, reply.id])
    #expect(manifest.root == ICloudSyncRecordID(kind: .page, id: root.id))
}

@Test @MainActor func spaceShareExcludesOtherSpacesAndRejectsUnknownRoot() throws {
    var snapshot = LibrarySnapshot(); let a = Space(title: "Shared"), b = Space(title: "Private")
    snapshot.spaces = [a, b]
    let page = Page(spaceID: a.id, title: "A"), privatePage = Page(spaceID: b.id, title: "B")
    snapshot.pages = [page, privatePage]
    #expect(try ICloudShareManifest(scope: .space(a.id), snapshot: snapshot).pages == [page.id])
    #expect(throws: LibraryError.invalidLibrary) { try ICloudShareManifest(scope: .space(UUID()), snapshot: snapshot) }
}
