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
    let renderGeneration = admission.nativeGeneration
    let callback: ([Block]) -> Bool = { admission.commit(library: f.library, page: page, token: token, generation: renderGeneration, blocks: $0) }
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
    let admission = PageBlockWritingAdmission()
    #expect(!admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: admission.nativeGeneration, blocks: [Block(id: f.blockID, markdown: "Unauthorized")]))
    #expect(f.token == nil)
    #expect(f.library.store?.snapshot.pages.first?.markdown.utf8.elementsEqual(original.markdown.utf8) == true)
}

@Test @MainActor func nativeBlockCallbackRejectsForeignChangeAfterItsOwnAcceptedWrite() throws {
    let f = try NativeWritingBindingFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let admission = PageBlockWritingAdmission()
    #expect(admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: admission.nativeGeneration, blocks: [Block(id: f.blockID, markdown: "Owned accepted")]))
    #expect(f.library.finishTyping(f.token))
    let store = try #require(f.library.store)
    try store.renamePage(f.page.id, title: "Foreign change")
    let expected = store.snapshot.pages
    #expect(!admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: admission.nativeGeneration, blocks: [Block(id: f.blockID, markdown: "Must not overwrite")]))
    #expect(store.snapshot.pages == expected)
}

@Test @MainActor func nativeWritingContinuesAfterConfirmedOwnTitleChange() throws {
    let f = try NativeWritingBindingFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let admission = PageBlockWritingAdmission()
    let source = "Owned e\u{301} 🦊\r\n"
    #expect(admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: admission.nativeGeneration, blocks: [Block(id: f.blockID, markdown: source)]))
    #expect(admission.finish(library: f.library))
    admission.refreshOwnedText(library: f.library, page: f.pageBinding)
    f.token = nil
    let previous = f.page
    let renderGeneration = admission.nativeGeneration
    f.page.title = "Renamed by this window"
    let result = try #require(f.library.processEditorNotification(previous: previous, changed: f.page, currentDraft: f.page, token: f.token))
    #expect(admission.acknowledge(result, library: f.library))
    #expect(admission.nativeGeneration == renderGeneration)
    f.token = result.token
    f.page.revision = try #require(result.revision)
    #expect(admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: admission.nativeGeneration, blocks: [Block(id: f.blockID, markdown: source + "continued")]))
    #expect(admission.finish(library: f.library))
    let disk = try LibraryStore(directory: try #require(f.library.store).directory)
    let saved = try #require(disk.snapshot.pages.first)
    #expect(saved.title == "Renamed by this window")
    #expect(saved.markdown.utf8.elementsEqual((source + "continued").utf8))
    #expect(saved.blocks.count == 1 && saved.blocks[0].id == f.blockID)
}

@Test @MainActor func nativeWritingRejectsReceiptAfterInterveningForeignChange() throws {
    let f = try NativeWritingBindingFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let admission = PageBlockWritingAdmission()
    #expect(admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: admission.nativeGeneration, blocks: [Block(id: f.blockID, markdown: "Owned")]))
    #expect(admission.finish(library: f.library))
    admission.refreshOwnedText(library: f.library, page: f.pageBinding); f.token = nil
    let previous = f.page; f.page.title = "Own title"
    let result = try #require(f.library.processEditorNotification(previous: previous, changed: f.page, currentDraft: f.page, token: nil))
    let store = try #require(f.library.store)
    try store.renamePage(f.page.id, title: "Other window title")
    let expected = store.snapshot.pages
    #expect(!admission.acknowledge(result, library: f.library))
    #expect(!admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: admission.nativeGeneration, blocks: [Block(id: f.blockID, markdown: "Rejected")]))
    #expect(store.snapshot.pages == expected)
}

@Test @MainActor func nativeWritingRejectsFailedMetadataMutationAndContinuesAcceptedText() throws {
    let f = try NativeWritingBindingFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let admission = PageBlockWritingAdmission()
    #expect(admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: admission.nativeGeneration, blocks: [Block(id: f.blockID, markdown: "Owned")]))
    admission.refreshOwnedText(library: f.library, page: f.pageBinding)
    let previous = f.page; f.page.title = "Unsaved"; f.page.revision = UUID()
    let result = try #require(f.library.processEditorNotification(previous: previous, changed: f.page, currentDraft: f.page, token: f.token))
    #expect(result.revision == nil && result.token == nil)
    #expect(!admission.acknowledge(result, library: f.library))
    #expect(admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: admission.nativeGeneration, blocks: [Block(id: f.blockID, markdown: "Owned continued")]))
    #expect(admission.finish(library: f.library))
    let saved = try #require(f.library.store?.snapshot.pages.first)
    #expect(saved.title == previous.title && saved.markdown == "Owned continued")
}

@Test(arguments: ["rules", "table", "image", "history", "quality", "purpose"])
@MainActor func nativeWritingContinuesAfterActualToolTransaction(kind: String) throws {
    let f = try NativeWritingBindingFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let admission = PageBlockWritingAdmission()
    let table = "| Key | Value |\n| --- | --- |\n| e\u{301} | 🦊 |\n"
    #expect(admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: admission.nativeGeneration, blocks: [Block(id: f.blockID, markdown: table)]))
    #expect(admission.finish(library: f.library))
    admission.refreshOwnedText(library: f.library, page: f.pageBinding); f.token = nil
    let store = try #require(f.library.store)
    let revision = f.page.revision
    let history = try #require(f.library.revisions.first(where: { $0.page.id == f.page.id }))
    let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
    let saved = try #require(admission.performToolMutation(library: f.library, pageID: f.page.id) {
        switch kind {
        case "rules": return f.library.savePageTools(pageID: f.page.id, baseRevision: revision, rules: "Rule e\u{301}", prompts: [])
        case "table": return f.library.replaceBlock(pageID: f.page.id, baseRevision: revision, blockID: f.blockID, expectedSource: table, replacement: table + "| Second | 2 |\n")
        case "image":
            do {
                _ = try store.addImageBlock(pageID: f.page.id, data: png, mediaType: "image/png", filename: "fixture.png", altText: "Fox", afterBlockID: f.blockID, baseRevision: revision)
                f.library.reload(); return f.library.currentPage(f.page.id)
            } catch { Issue.record(error); return nil }
        case "history": return f.library.restore(history, baseRevision: revision)
        case "quality":
            var corrected = f.page; corrected.markdown = table.replacingOccurrences(of: "Value", with: "Meaning")
            guard f.library.update(corrected) != nil else { return nil }
            return f.library.currentPage(f.page.id)
        default: return f.library.changePurpose(f.page, purpose: .material)
        }
    })
    f.page = saved
    var blocks = try #require(store.snapshot.pages.first).blocks
    let ids = blocks.map(\.id)
    blocks[0].markdown += "continued Café 🦊."
    #expect(admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: admission.nativeGeneration, blocks: blocks))
    #expect(admission.finish(library: f.library))
    let disk = try LibraryStore(directory: store.directory)
    let stored = try #require(disk.snapshot.pages.first)
    #expect(stored.blocks.map(\.id) == ids)
    #expect(stored.markdown.utf8.elementsEqual(blocks.map(\.markdown).joined().utf8))
    if kind == "rules" { #expect(stored.assistantRules == "Rule e\u{301}") }
    if kind == "image" { #expect(try disk.attachmentData(#require(stored.attachments?.first)) == png) }
}

@Test @MainActor func nativeToolMutationRejectsForeignChangesBeforeCallingTool() throws {
    let f = try NativeWritingBindingFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let admission = PageBlockWritingAdmission()
    #expect(admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: admission.nativeGeneration, blocks: [Block(id: f.blockID, markdown: "Owned")]))
    #expect(admission.finish(library: f.library))
    let store = try #require(f.library.store)
    try store.renamePage(f.page.id, title: "Foreign")
    let expected = store.snapshot.pages; var called = false
    #expect(admission.performToolMutation(library: f.library, pageID: f.page.id, operation: { called = true; return f.page }) == nil)
    #expect(!called && store.snapshot.pages == expected)
}

@Test @MainActor func nativeToolMutationFailureCannotAdoptPartiallyChangedPage() throws {
    let f = try NativeWritingBindingFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let admission = PageBlockWritingAdmission()
    #expect(admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: admission.nativeGeneration, blocks: [Block(id: f.blockID, markdown: "Owned")]))
    #expect(admission.finish(library: f.library))
    let store = try #require(f.library.store)
    #expect(admission.performToolMutation(library: f.library, pageID: f.page.id, operation: {
        try? store.renamePage(f.page.id, title: "Partial tool write")
        f.library.reload(); return nil
    }) == nil)
    let expected = store.snapshot.pages
    #expect(!admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: admission.nativeGeneration, blocks: [Block(id: f.blockID, markdown: "Must not overwrite")]))
    #expect(store.snapshot.pages == expected)
}

@Test @MainActor func nativeToolTransitionRejectsQueuedPreToolBlockProposal() throws {
    let f = try NativeWritingBindingFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let admission = PageBlockWritingAdmission()
    let renderGeneration = admission.nativeGeneration
    let oldBlocks = [Block(id: f.blockID, markdown: "| Key | Value |\n| --- | --- |\n| Source | 1 |\n")]
    #expect(admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: renderGeneration, blocks: oldBlocks))
    #expect(admission.finish(library: f.library))
    admission.refreshOwnedText(library: f.library, page: f.pageBinding); f.token = nil
    let saved = try #require(admission.performToolMutation(library: f.library, pageID: f.page.id) {
        f.library.replaceBlock(pageID: f.page.id, baseRevision: f.page.revision, blockID: f.blockID, expectedSource: oldBlocks[0].markdown, replacement: oldBlocks[0].markdown.replacingOccurrences(of: "1", with: "12"))
    })
    f.page = saved
    let expected = try #require(f.library.store).snapshot.pages
    // A callback prepared before the tool must not restore the old table.
    #expect(!admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: renderGeneration, blocks: oldBlocks))
    #expect(f.library.store?.snapshot.pages == expected)
}

@Test @MainActor func nativeTextReplacementInvalidatesOldCallbacksButKeepsNewJournal() throws {
    let f = try NativeWritingBindingFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let admission = PageBlockWritingAdmission()
    let generation = admission.nativeGeneration
    let oldBlocks = [Block(id: f.blockID, markdown: "Owned")]
    #expect(admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: generation, blocks: oldBlocks))
    #expect(admission.finish(library: f.library))
    admission.refreshOwnedText(library: f.library, page: f.pageBinding); f.token = nil
    let previous = f.page; f.page.markdown = "Corrected Café 🦊."
    let result = try #require(f.library.processEditorNotification(previous: previous, changed: f.page, currentDraft: f.page, token: nil))
    #expect(admission.acknowledge(result, library: f.library))
    #expect(admission.nativeGeneration != generation)
    f.token = result.token; f.page.revision = try #require(result.revision)
    let store = try #require(f.library.store), expected = store.snapshot.pages
    #expect(!admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: generation, blocks: oldBlocks))
    #expect(store.snapshot.pages == expected)
    var current = try #require(store.snapshot.pages.first).blocks; current[0].markdown += " continued"
    #expect(admission.commit(library: f.library, page: f.pageBinding, token: f.tokenBinding, generation: admission.nativeGeneration, blocks: current))
    #expect(admission.finish(library: f.library))
    #expect(store.hasActiveEdits == false)
    #expect(store.snapshot.pages.first?.markdown == "Corrected Café 🦊. continued")
}
