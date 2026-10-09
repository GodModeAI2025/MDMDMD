import Foundation
import Testing
import SkriptumCore
@testable import SkriptumBlocks
struct CompositeBlockTests {
    @Test(arguments: ["# Title\r\n\r\n😀 e\u{301} body\r\n", "# Title\nbody", "```\ncode\n```\n\nbody\n", "> quote\n\nbody\n", "- item\n\nbody\n", "![alt](media/00000000-0000-0000-0000-000000000001)\n\nbody\n"])
    func compositeSourceIsRaw(_ source: String) {
        let id = UUID(), stored = [Block(id: id, markdown: source)]
        let projection = BlockProjection(source)
        #expect(projection.isRawSource)
        #expect(projection.kind == .paragraph && projection.headingLevel == 0)
        #expect(projection.text.utf8.elementsEqual(source.utf8))
        #expect(projection.replacingText(projection.text).utf8.elementsEqual(source.utf8))
        let edited = source + "追加"
        let changed = BlockEditing.replacing(stored,id: id,text: edited)
        #expect(changed.count == 1 && changed[0].id == id)
        #expect(changed[0].markdown.utf8.elementsEqual(edited.utf8))
        #expect(projection.sourceOffset(for: source.utf16.count) == source.utf16.count)
        #expect(projection.bodyOffset(forSourceOffset: source.utf16.count) == source.utf16.count)
        #expect(BlockEditing.initialBlocks(markdown: source, stored: stored) == stored)
    }
    @Test(arguments: ["# Heading\r\n\r\n", "```\r\n# code\r\n\r\nbody\r\n```\r\n", "- one\n- two\n", "> quote\n> next\n"])
    func ordinaryRowsRetainProjection(_ source: String) {
        let projection = BlockProjection(source)
        #expect(!projection.isRawSource)
        #expect(projection.replacingText(projection.text).utf8.elementsEqual(source.utf8))
    }
    @Test func rawLineStylingTargetsSelectionAndRejectsCode() {
        let source = "# Title\r\n\r\nbody 😀\r\n\r\n```\r\ncode\r\n```\r\n"
        let projection = BlockProjection(source)
        #expect(projection.isRawSource)
        let bodyRange = (source as NSString).range(of: "body 😀")
        let command = BlockEditorCommand(prefix: "## ", suffix: "")
        let edit = MarkdownLineStyling.applying(command, to: source, selection: bodyRange)
        #expect(edit?.source == source.replacingOccurrences(of: "body 😀", with: "## body 😀"))
        let codeRange = (source as NSString).range(of: "code")
        #expect(MarkdownLineStyling.applying(command, to: source, selection: codeRange) == nil)
    }

}
