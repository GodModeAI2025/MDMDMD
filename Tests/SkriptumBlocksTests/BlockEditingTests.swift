import Foundation
import Testing
@testable import SkriptumBlocks
import SkriptumCore

struct BlockEditingTests {
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
