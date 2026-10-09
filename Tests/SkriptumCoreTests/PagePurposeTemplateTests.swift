import Foundation
import Testing
@testable import SkriptumCore

@MainActor struct PagePurposeTemplateTests {
    func store() throws -> LibraryStore { try LibraryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) }
    @Test func legacyAndEligibility() throws {
        let store = try store(); let space = try store.createSpace(title: "Book")
        let writing = try store.createPage(spaceID: space.id, title: "Chapter", markdown: "one two")
        let material = try store.createPage(spaceID: space.id, title: "Research", markdown: "three four five")
        let template = try store.createPage(spaceID: space.id, title: "Template", markdown: "six")
        let legacy = try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(writing))
        #expect(legacy.purpose == nil); #expect(legacy.effectivePurpose == .writing)
        try store.setPurpose(pageID: material.id, purpose: .material, baseRevision: material.revision)
        try store.setPurpose(pageID: template.id, purpose: .template, baseRevision: template.revision)
        #expect(store.manuscriptPages(spaceID: space.id).map(\.id) == [writing.id])
        #expect(store.aggregateWordCount(spaceID: space.id, countWords: { $0.split(separator: " ").count }) == 2)
        let reopened = try LibraryStore(directory: store.directory)
        #expect(reopened.snapshot.pages.first(where: { $0.id == material.id })?.purpose == .material)
    }
    @Test func templateCopyPreservesBytesMetadataAndFreshIdentity() throws {
        let store = try store(); let sourceSpace = try store.createSpace(title: "Templates"); let target = try store.createSpace(title: "Book")
        var page = try store.createPage(spaceID: sourceSpace.id, title: "Draft", markdown: "# E\u{301} 😄\r\n\r\nText\r\n")
        try store.setRules(pageID: page.id, rules: "Preserve", baseRevision: page.revision)
        page = store.snapshot.pages.first { $0.id == page.id }!
        try store.setPrompts(pageID: page.id, prompts: [ReusablePrompt(title: "Edit", text: "Keep voice")], baseRevision: page.revision)
        page = store.snapshot.pages.first { $0.id == page.id }!
        try store.setWordGoal(pageID: page.id, goal: 1200, baseRevision: page.revision)
        try store.setTags(page.id, tags: ["chapter"])
        page = store.snapshot.pages.first { $0.id == page.id }!
        try store.setPurpose(pageID: page.id, purpose: .template, baseRevision: page.revision)
        let original = store.snapshot.pages.first { $0.id == page.id }!; let history = store.snapshot.revisions
        let copy = try store.instantiateTemplate(pageID: original.id, baseRevision: original.revision, spaceID: target.id)
        #expect(copy.id != original.id && copy.revision != original.revision)
        #expect(Set(copy.blocks.map(\.id)).isDisjoint(with: original.blocks.map(\.id)))
        #expect(Data(copy.markdown.utf8) == Data(original.markdown.utf8))
        #expect(copy.effectivePurpose == .writing && copy.spaceID == target.id)
        #expect(copy.assistantRules == original.assistantRules && copy.reusablePrompts == original.reusablePrompts)
        #expect(copy.wordGoal == original.wordGoal && copy.tags == original.tags)
        #expect(store.snapshot.pages.first { $0.id == original.id } == original)
        #expect(store.snapshot.revisions == history)
    }
    @Test func rejectedOperationsAndDiskFailureAreAtomic() throws {
        let store = try store(); let space = try store.createSpace(title: "Book"); let page = try store.createPage(spaceID: space.id, title: "Template")
        #expect(throws: LibraryError.invalidTemplate) { try store.instantiateTemplate(pageID: page.id, baseRevision: page.revision, spaceID: space.id) }
        try store.setPurpose(pageID: page.id, purpose: .template, baseRevision: page.revision)
        let template = store.snapshot.pages[0]; let before = store.snapshot
        #expect(throws: LibraryError.revisionConflict) { try store.setPurpose(pageID: page.id, purpose: .material, baseRevision: page.revision) }
        #expect(throws: LibraryError.missingSpace) { try store.instantiateTemplate(pageID: page.id, baseRevision: template.revision, spaceID: UUID()) }
        #expect(throws: LibraryError.missingPage) { try store.instantiateTemplate(pageID: page.id, baseRevision: template.revision, spaceID: space.id, parentID: UUID()) }
        let token = try store.beginEditing(pageID: page.id, baseRevision: template.revision)
        #expect(throws: LibraryError.editInProgress) { try store.setPurpose(pageID: page.id, purpose: .material, baseRevision: template.revision) }
        #expect(throws: LibraryError.editInProgress) { try store.instantiateTemplate(pageID: page.id, baseRevision: template.revision, spaceID: space.id) }
        try store.finishEditing(token)
        let file = store.directory.appendingPathComponent("library.json")
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try store.instantiateTemplate(pageID: page.id, baseRevision: template.revision, spaceID: space.id) }
        #expect(store.snapshot == before)
    }
    @Test func templateMediaAndInvalidSourceParent() throws {
        let store = try store(); let space = try store.createSpace(title: "Templates"); let other = try store.createSpace(title: "Book")
        let page = try store.createPage(spaceID: space.id, title: "Image")
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        let attachment = try store.addAttachment(pageID: page.id, data: bytes, mediaType: "image/png", filename: "image.png", baseRevision: page.revision)
        var template = store.snapshot.pages[0]
        try store.setPurpose(pageID: page.id, purpose: .template, baseRevision: template.revision)
        template = store.snapshot.pages[0]
        let copy = try store.instantiateTemplate(pageID: page.id, baseRevision: template.revision, spaceID: other.id)
        #expect(copy.attachments == template.attachments)
        #expect(try store.attachmentData(copy.attachments![0]) == bytes)
        #expect(throws: LibraryError.crossSpaceParent) { try store.instantiateTemplate(pageID: page.id, baseRevision: template.revision, spaceID: other.id, parentID: page.id) }
        let before = store.snapshot
        try Data([0]).write(to: store.directory.appendingPathComponent(attachment.relativePath))
        #expect(throws: LibraryError.invalidAttachment) { try store.instantiateTemplate(pageID: page.id, baseRevision: template.revision, spaceID: other.id) }
        #expect(store.snapshot == before)
        try bytes.write(to: store.directory.appendingPathComponent(attachment.relativePath))
        try store.trashPage(copy.id)
        #expect(throws: LibraryError.trashedParent) { try store.instantiateTemplate(pageID: page.id, baseRevision: template.revision, spaceID: other.id, parentID: copy.id) }
        try store.trashPage(page.id)
        template = store.snapshot.pages[0]
        #expect(throws: LibraryError.invalidTemplate) { try store.instantiateTemplate(pageID: page.id, baseRevision: template.revision, spaceID: other.id) }
    }

}
