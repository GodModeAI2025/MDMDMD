import Foundation
import SwiftUI
import Testing
import SkriptumCore
@testable import SkriptumWorkspaceModel

@MainActor private final class NativeWritingBindingFixture {
    let root: URL, library: WritingLibrary
    var page: WritingPage
    var token: UUID?
    let blockID: UUID
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ScriptumLiveWritingBindings-" + UUID().uuidString)
        let documents = root.appendingPathComponent("Documents")
        let store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
        let space = try store.createSpace(title: "Writing")
        let original = try store.createPage(spaceID: space.id, title: "Native", markdown: "# Header\r\n\r\nBody e\u{301} 🦊\r\n")
        blockID = UUID()
        try store.setBlocks(pageID: original.id, blocks: [Block(id: blockID, markdown: original.markdown)], baseRevision: original.revision)
        library = try WritingLibrary(store: store, documentRoot: documents, supportRoot: root.appendingPathComponent("Support"), preferences: UserDefaults(suiteName: UUID().uuidString)!)
        page = try #require(library.pages.first)
    }
    var pageBinding: Binding<WritingPage> { Binding(get: { self.page }, set: { self.page = $0 }) }
    var tokenBinding: Binding<UUID?> { Binding(get: { self.token }, set: { self.token = $0 }) }
}

@Test @MainActor func nativeBlockCallbackReadsLiveRevisionAcrossManyWritesWithoutNewRender() throws {
    let f = try NativeWritingBindingFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let initial = f.page
    // Model an old native callback whose scalar getters keep the render snapshot.
    let page = Binding(get: { initial }, set: { f.page = $0 })
    let token = Binding<UUID?>(get: { nil }, set: { f.token = $0 })
    let admission = PageBlockWritingAdmission()
    let callback: ([Block]) -> Bool = { admission.commit(library: f.library, page: page, token: token, blocks: $0) }
    var source = f.page.markdown
    for scalar in "ABCDEFGHIJKLMNOP Café 🦊.".unicodeScalars {
        source.unicodeScalars.append(scalar)
        #expect(callback([Block(id: f.blockID, markdown: source)]))
    }
    #expect(admission.finish(library: f.library))
    admission.refreshOwnedText(library: f.library, page: page)
    #expect(f.page.markdown.utf8.elementsEqual(source.utf8))
    #expect(f.library.store?.hasActiveEdits == false)
    let restored = try LibraryStore(directory: try #require(f.library.store).directory)
    let saved = try #require(restored.snapshot.pages.first)
    #expect(saved.blocks.count == 1 && saved.blocks[0].id == f.blockID)
    #expect(saved.markdown.utf8.elementsEqual(source.utf8))
}
@Test @MainActor func nativeBlockCallbackStillRejectsStaleAuthorityWithoutUpdatingBinding() throws {
    let f = try NativeWritingBindingFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let original = f.page
    f.page.revision = UUID()
    #expect(!PageBlockWritingAdmission().commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, blocks: [Block(id: f.blockID, markdown: "Unauthorized")]))
    #expect(f.token == nil)
    #expect(f.library.store?.snapshot.pages.first?.markdown.utf8.elementsEqual(original.markdown.utf8) == true)
}

@Test @MainActor func nativeBlockCallbackRejectsForeignChangeAfterItsOwnAcceptedWrite() throws {
    let f = try NativeWritingBindingFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let admission = PageBlockWritingAdmission()
    #expect(admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, blocks: [Block(id: f.blockID, markdown: "Owned accepted")]))
    #expect(f.library.finishTyping(f.token))
    let store = try #require(f.library.store)
    try store.renamePage(f.page.id, title: "Foreign change")
    let expected = store.snapshot.pages
    #expect(!admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, blocks: [Block(id: f.blockID, markdown: "Must not overwrite")]))
    #expect(store.snapshot.pages == expected)
}
