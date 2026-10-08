import Foundation
import Testing
@testable import SkriptumBlocks
import SkriptumCore

struct BlockEditingTests {
    @Test func lineStylesReplaceStructureAtMidlineAndPreserveExactUndo() throws {
        let heading = BlockEditorCommand(prefix: "## ", suffix: "")
        let list = BlockEditorCommand(prefix: "- ", suffix: "")
        let examples: [(String, NSRange, BlockEditorCommand, String)] = [
            ("A B\r\n\r\n", NSRange(location: 2, length: 0), heading, "## A B\r\n\r\n"),
            ("# Title\r\n\r\n", NSRange(location: 2, length: 5), heading, "## Title\r\n\r\n"),
            ("## 😀Cafe\u{301}\r\n\r\n", NSRange(location: 5, length: 0), list, "- 😀Cafe\u{301}\r\n\r\n"),
            ("3. First\r\n4. Second\r\n\r\n", NSRange(location: 0, length: 19), list, "- First\r\n- Second\r\n\r\n")
        ]
        for (source, selection, command, expected) in examples {
            let result = try #require(MarkdownLineStyling.applying(command, to: source, selection: selection))
            #expect(result.source.utf8.elementsEqual(expected.utf8))
            #expect(result.undoSource.utf8.elementsEqual(source.utf8))
            #expect(result.undoSelection == selection)
        }
        let image = "![A](media/" + UUID().uuidString + ")\n\n"
        #expect(MarkdownLineStyling.applying(heading, to: image, selection: NSRange(location: 4, length: 0)) == nil)
        #expect(MarkdownLineStyling.applying(list, to: "```swift\r\nlet value = 1\r\n```\r\n", selection: NSRange(location: 14, length: 0)) == nil)
        let sourceModeCode = "```swift\nA\n```"
        let originalBytes = Array(sourceModeCode.utf8)
        let bodyCaret = (sourceModeCode as NSString).range(of: "A").location
        #expect(MarkdownLineStyling.applying(heading, to: sourceModeCode, selection: NSRange(location: bodyCaret, length: 0)) == nil)
        #expect(Array(sourceModeCode.utf8) == originalBytes)
    }
    @Test func inlineFormattingPreservesUnicodeSourceDelimitersAndIDs() throws {
        let blocks = [Block(markdown: "## 😀Cafe\u{301}\r\n\r\n"), Block(markdown: "Untouched\r\n \r\n")]
        let projection = BlockProjection(blocks[0].markdown)
        let command = BlockEditorCommand(prefix: "**", suffix: "**")
        let edit = try #require(BlockCommandEditing.applying(command, to: projection.text, selection: NSRange(location: 2, length: 5)))
        #expect(edit.text == "😀**Cafe\u{301}**")
        #expect(edit.selection == NSRange(location: 4, length: 5))
        let result = BlockEditing.replacing(blocks, id: blocks[0].id, text: edit.text)
        #expect(result[0].markdown.utf8.elementsEqual("## 😀**Cafe\u{301}**\r\n\r\n".utf8))
        #expect(result[0].id == blocks[0].id)
        #expect(result[1].markdown.utf8.elementsEqual(blocks[1].markdown.utf8))
        #expect(result[1].id == blocks[1].id)
        #expect(BlockCommandEditing.applying(command, to: "😀", selection: NSRange(location: 1, length: 0)) == nil)
        #expect(BlockCommandEditing.applying(command, to: "text", selection: NSRange(location: 9, length: 0)) == nil)
    }
    @Test func formattingCaretAndMultilineListKeepOriginalMarkers() throws {
        let projection = BlockProjection("3. first\r\n4. second\r\n\r\n")
        let command = BlockEditorCommand(prefix: "*", suffix: "*")
        let edit = try #require(BlockCommandEditing.applying(command, to: projection.text, selection: NSRange(location: 6, length: 6)))
        #expect(projection.replacingText(edit.text) == "3. first\r\n4. *second*\r\n\r\n")
        let caret = try #require(BlockCommandEditing.applying(command, to: "😀", selection: NSRange(location: 2, length: 0)))
        #expect(caret.text == "😀**")
        #expect(caret.selection == NSRange(location: 3, length: 0))
    }
    @Test func formattingCommandAcknowledgesEachTokenOnlyOnce() {
        let command = BlockEditorCommand(prefix: "**", suffix: "**")
        var nativeGate = BlockCommandGate(), callbackGate = BlockCommandGate()
        var applications = 0, acknowledgements = 0
        for _ in 0..<4 {
            if nativeGate.claim(command.id) { applications += 1 }
            if callbackGate.claim(command.id) { acknowledgements += 1 }
        }
        #expect(applications == 1)
        #expect(acknowledgements == 1)
        let newTokenAccepted = nativeGate.claim(UUID())
        #expect(newTokenAccepted)
    }
    @Test func outlineCaretMapsHeadingsCRLFEmojiAndFencedCode() throws {
        let source = "## 😀Title\r\n\r\n~~~swift\r\nx😀\r\nsecond\r\n~~~\r\n\r\nEnd"
        let blocks = MarkdownReconciler.reconcile(source, previous: [])
        let heading = try #require(BlockCommandEditing.caretTarget(in: blocks, sourceOffset: 0))
        #expect(heading.blockID == blocks[0].id)
        #expect(heading.selection == NSRange(location: 0, length: 0))
        let headingEmoji = (source as NSString).range(of: "😀Title").location
        #expect(BlockCommandEditing.caretTarget(in: blocks, sourceOffset: headingEmoji + 2)?.selection.location == 2)
        #expect(BlockCommandEditing.caretTarget(in: blocks, sourceOffset: headingEmoji + 1)?.selection.location == 0)
        let codeStart = (source as NSString).range(of: "x😀").location
        let code = try #require(BlockCommandEditing.caretTarget(in: blocks, sourceOffset: codeStart + 3))
        #expect(code.blockID == blocks[1].id)
        #expect(code.selection.location == 3)
        let secondLine = (source as NSString).range(of: "second").location
        #expect(BlockCommandEditing.caretTarget(in: blocks, sourceOffset: secondLine)?.selection.location == 4)
        let fenceEnd = (source as NSString).range(of: "~~~\r\n\r\nEnd").location
        #expect(BlockCommandEditing.caretTarget(in: blocks, sourceOffset: fenceEnd)?.selection.location == "x😀\nsecond".utf16.count)
        #expect(BlockCommandEditing.caretTarget(in: [], sourceOffset: 0) == nil)
    }
    @Test @MainActor func coreImageInsertionOwnsLeadingBoundariesWithoutHidingRaster() throws {
        let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        for source in ["End", "End\n", "End\r\n", "End\n\n", "End\r\n\r\n"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try LibraryStore(directory: directory)
            let space = try store.createSpace(title: "Images")
            let page = try store.createPage(spaceID: space.id, title: "Boundaries", markdown: source)
            let result = try store.addImageBlock(pageID: page.id, data: pixel, mediaType: "image/png", filename: "pixel.png", altText: "Pixel 😀", afterBlockID: page.blocks.last?.id, baseRevision: page.revision)
            let image = try #require(result.page.blocks.last)
            #expect(result.page.blocks[0].markdown.utf8.elementsEqual(source.utf8))
            let projection = BlockProjection(image.markdown)
            #expect(projection.kind == .image)
            #expect(projection.text == "![Pixel 😀](" + result.attachment.relativePath + ")")
            #expect(projection.replacingText(projection.text).utf8.elementsEqual(image.markdown.utf8))
            #expect(BlockImageReference(image.markdown)?.target == result.attachment.relativePath)
            #expect(BlockImageReference(image.markdown)?.altText == "Pixel 😀")
            #expect(try Data(contentsOf: directory.appendingPathComponent(result.attachment.relativePath)) == pixel)
            let replacement = projection.text.replacingOccurrences(of: "Pixel 😀", with: "Changed")
            #expect(projection.replacingText(replacement).utf8.elementsEqual(image.markdown.replacingOccurrences(of: "Pixel 😀", with: "Changed").utf8))
        }
    }
    @Test func imageBlocksPreserveSourceAndHaveAccessibleAltReference() {
        let id = UUID().uuidString
        let source = "![Fels \\[West\\] 😀](media/\(id))\r\n\r\n"
        let projection = BlockProjection(source)
        #expect(projection.kind == .image)
        #expect(projection.replacingText(projection.text).utf8.elementsEqual(source.utf8))
        #expect(BlockImageReference(source)?.altText == "Fels [West] 😀")
        #expect(BlockImageReference(source)?.target == "media/" + id)
        #expect(BlockImageReference("![Bild](media/\(id))\r\n \r\n")?.target == "media/" + id)
        #expect(BlockImageReference("![A](https://example.com/a.png)") == nil)
        #expect(BlockImageReference("![A](media/../outside)") == nil)
        #expect(BlockProjection(source + "Other paragraph").kind != .image)
    }
    @Test func rejectedDomainTransactionCannotPublishChangedTextOrIDs() {
        let stored = [Block(markdown: "repeat\n\n"), Block(markdown: "repeat\n\n")]
        let reordered = BlockEditing.moving(stored, id: stored[1].id, before: stored[0].id)
        var calls = 0
        let rejected = BlockEditing.acceptedProposal(reordered) { proposal in
            calls += 1
            #expect(proposal.map(\.id) == [stored[1].id, stored[0].id])
            return false
        }
        #expect(rejected == nil)
        #expect(calls == 1)
        let changed = BlockEditing.replacing(stored, id: stored[0].id, text: "changed")
        #expect(BlockEditing.acceptedProposal(changed, accept: { _ in false }) == nil)
        #expect(BlockEditing.acceptedProposal(reordered, accept: { _ in true })?.map(\.id) == reordered.map(\.id))
    }
    @Test func storedIDsAndExplicitReorderedArrayArePreserved() {
        let stored = [Block(markdown: "repeat\n\n"), Block(markdown: "repeat\n\n"), Block(markdown: "last\n\n")]
        let initial = BlockEditing.initialBlocks(markdown: stored.map(\.markdown).joined(), stored: stored)
        #expect(initial.map(\.id) == stored.map(\.id))
        let reordered = BlockEditing.moving(initial, id: initial[1].id, before: initial[0].id)
        #expect(reordered.map(\.id) == [stored[1].id, stored[0].id, stored[2].id])
        let readback = BlockEditing.initialBlocks(markdown: reordered.map(\.markdown).joined(), stored: reordered)
        #expect(readback.map(\.id) == reordered.map(\.id))
    }
    @Test func untouchedUnicodeAndSeparatorsSurviveEdits() {
        let source = "# Cafe\u{301}\r\n\r\n\tuntouched 😀\r\n \r\n- first\r\n- second\r\n\r\n"
        let blocks = MarkdownReconciler.reconcile(source, previous: [])
        let edited = BlockEditing.replacing(blocks, id: blocks[0].id, text: "New heading")
        #expect(edited[0].markdown == "# New heading\r\n\r\n")
        for index in blocks.indices.dropFirst() {
            #expect(edited[index].markdown.utf8.elementsEqual(blocks[index].markdown.utf8))
            #expect(edited[index].id == blocks[index].id)
        }
    }
    @Test func projectionRoundTripsRealSyntax() {
        let examples = ["## Heading\r\n\r\n", "3. one\n4. two\n\n", "- [x] done\n- [ ] open\n\n", "> quoted\n> continuation\n\n", "~~~swift\nlet x = 1\n\nprint(x)\n~~~\n\n", "```\n```\n\n", "e\u{301} 😀\n \n", ""]
        for example in examples {
            let projection = BlockProjection(example)
            #expect(projection.replacingText(projection.text).utf8.elementsEqual(example.utf8))
        }
    }
    @Test func listEditsKeepMarkersAndNewlineStyle() {
        let projection = BlockProjection("3. one\r\n4. two\r\n\r\n")
        #expect(projection.text == "one\ntwo")
        #expect(projection.replacingText("ONE\nTWO") == "3. ONE\r\n4. TWO\r\n\r\n")
        #expect(projection.sourceOffset(for: 4) == 11)
    }
    @Test func fencedCodePreservesFenceAndInternalBlankLines() {
        let projection = BlockProjection("~~~swift\r\nlet a = 1\r\n\r\nprint(a)\r\n~~~\r\n\r\n")
        #expect(projection.kind == .code)
        #expect(projection.replacingText("let a = 2\n\nprint(a)") == "~~~swift\r\nlet a = 2\r\n\r\nprint(a)\r\n~~~\r\n\r\n")
        #expect(BlockProjection("```\n```\n\n").replacingText("new code") == "```\nnew code\n```\n\n")
    }
    @Test func moveAndDuplicateDoNotFuseLastParagraph() {
        let blocks = MarkdownReconciler.reconcile("first\n\nlast", previous: [])
        let moved = BlockEditing.moving(blocks, id: blocks[1].id, before: blocks[0].id)
        #expect(moved.map(\.id) == [blocks[1].id, blocks[0].id])
        #expect(MarkdownReconciler.fragments(moved.map(\.markdown).joined()).count == 2)
        let duplicate = BlockEditing.duplicating(blocks, id: blocks[1].id)
        #expect(duplicate[1].id != duplicate[2].id)
        #expect(MarkdownReconciler.fragments(duplicate.map(\.markdown).joined()).count == 3)
    }
    @Test func deleteKeepsEditorUsableAndInsertionPreservesNeighbours() {
        let blocks = MarkdownReconciler.reconcile("before\n\nafter\n\n", previous: [])
        let inserted = BlockEditing.inserting(blocks, after: blocks[0].id, markdown: "## Insert\n\n")
        #expect(inserted[0].markdown.utf8.elementsEqual(blocks[0].markdown.utf8))
        #expect(inserted[2].markdown.utf8.elementsEqual(blocks[1].markdown.utf8))
        #expect(BlockEditing.deleting([blocks[0]], id: blocks[0].id).count == 1)
    }
    @Test func taskToggleChangesOnlyCheckboxByte() {
        let block = Block(markdown: "- [ ] first\r\n- [X] second\r\n\r\n")
        let result = BlockEditing.togglingTask([block], id: block.id, line: 1)
        #expect(result[0].markdown == "- [ ] first\r\n- [ ] second\r\n\r\n")
        #expect(result[0].id == block.id)
    }
    @Test func unicodeSelectionUsesUTF16SourceOffsets() {
        let projection = BlockProjection("# 😀e\u{301}\n\n")
        #expect(projection.sourceOffset(for: 2) == 4)
        #expect(projection.sourceOffset(for: 4) == 6)
    }
}
