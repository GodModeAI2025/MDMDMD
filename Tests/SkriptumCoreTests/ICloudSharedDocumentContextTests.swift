import Foundation
import Testing
@testable import SkriptumCore

@Test @MainActor func pageShareRetainsCanonicalExternalAncestryAndEnforcesPermission() throws {
    let space = UUID(), external = UUID()
    let root = Page(spaceID: space, parentID: external, title: "Shared", markdown: "e\u{301}\r\n")
    let child = Page(spaceID: space, parentID: root.id, title: "Child")
    var canonical = LibrarySnapshot(); canonical.pages = [root, child]
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    let bytes = try encoder.encode(canonical)
    let context = try ICloudSharedDocumentContext(root: .init(kind: .page, id: root.id), canonical: canonical, permission: .readOnly)
    #expect(try encoder.encode(context.canonical) == bytes)
    #expect(context.page(root.id)?.parentID == external)
    #expect(context.visibleParent(of: root.id) == nil)
    #expect(context.visibleParent(of: child.id) == root.id)
    #expect(context.page(external) == nil)
    #expect(throws: ICloudSharedDocumentError.permissionDenied) { try context.requireWrite(to: child.id) }
    let writable = try ICloudSharedDocumentContext(root: context.root, canonical: canonical, permission: .readWrite)
    try writable.requireWrite(to: child.id)
    #expect(throws: ICloudSharedDocumentError.permissionDenied) { try writable.requireWrite(to: external) }
    let revoked = try ICloudSharedDocumentContext(root: context.root, canonical: canonical, permission: .revoked)
    #expect(revoked.page(root.id) == nil)
}

@Test @MainActor func sharedContextRejectsUnrelatedPagesAndMissingInternalParents() throws {
    let root = Page(spaceID: UUID(), title: "Shared")
    var snapshot = LibrarySnapshot(); snapshot.pages = [root, Page(spaceID: root.spaceID, title: "Private sibling")]
    #expect(throws: ICloudSharedDocumentError.outsideShare) {
        try ICloudSharedDocumentContext(root: .init(kind: .page, id: root.id), canonical: snapshot, permission: .readWrite)
    }
    snapshot.pages = [root, Page(spaceID: root.spaceID, parentID: UUID(), title: "Missing parent")]
    #expect(throws: ICloudSharedDocumentError.incompleteHierarchy) {
        try ICloudSharedDocumentContext(root: .init(kind: .page, id: root.id), canonical: snapshot, permission: .readWrite)
    }
}
