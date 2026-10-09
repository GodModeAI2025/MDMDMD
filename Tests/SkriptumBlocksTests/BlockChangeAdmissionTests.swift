import Testing
import SkriptumCore
@testable import SkriptumBlocks
@Test func changeAdmissionUsesCurrentBytesAndIdentity() {
    #expect(!BlockChangeAdmission.acceptsMarkdown(event:"partial",current:"partial full"))
    #expect(BlockChangeAdmission.acceptsMarkdown(event:"baseline",current:"baseline"))
    #expect(!BlockChangeAdmission.acceptsMarkdown(event:"é",current:"e\u{301}"))
    let first = Block(markdown:"a"), second = Block(markdown:"b")
    #expect(BlockChangeAdmission.acceptsBlocks(event:[first,second],canonical:[first,second]))
    #expect(!BlockChangeAdmission.acceptsBlocks(event:[second,first],canonical:[first,second]))
    #expect(!BlockChangeAdmission.acceptsBlocks(event:[Block(markdown:"a"),second],canonical:[first,second]))
    #expect(BlockChangeAdmission.acceptsBlocks(event:[first],canonical:nil))
    let composed = Block(id: first.id, markdown: "é"), decomposed = Block(id: first.id, markdown: "e\u{301}")
    #expect(!BlockChangeAdmission.acceptsBlocks(event:[composed],canonical:[decomposed]))
}
