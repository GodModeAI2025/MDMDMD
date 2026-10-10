import Foundation
import Testing
@testable import SkriptumBlocks

@Test func compositePresentationRetainsExactSourceAndSemanticUTF16Ranges() throws {
    let source = "# Café 🦊\r\n\r\nProse e\u{301} **strong** and *italic*.\r\n\r\n```swift\r\n# protected\r\n```\r\n"
    let plan = try MarkdownSourcePresentation(source: source)
    #expect(plan.source.utf8.elementsEqual(source.utf8))
    let ns = source as NSString
    #expect(plan.runs.contains { $0.style == .heading(1) && ns.substring(with: $0.range).contains("Café 🦊") })
    #expect(plan.runs.filter { if case .heading = $0.style { true } else { false } }.count == 1)
    #expect(plan.runs.contains { $0.style == .strong && ns.substring(with: $0.range) == "**strong**" })
    #expect(plan.runs.contains { $0.style == .emphasis && ns.substring(with: $0.range) == "*italic*" })
    #expect(plan.runs.contains { $0.style == .code && ns.substring(with: $0.range).contains("# protected") })
    for run in plan.runs { #expect(run.range.location >= 0 && NSMaxRange(run.range) <= ns.length) }
}
@Test func compositePresentationHandlesSetextNestedUnicodeAndFinalLine() throws {
    let source = "🦊 **e\u{301}**\n\nTitle\n=====\n\n> ## Nested\n> Paragraph `🦊`\n\nFinal *word*"
    let plan = try MarkdownSourcePresentation(source: source)
    let ns = source as NSString
    #expect(plan.runs.contains { $0.style == .heading(1) && ns.substring(with: $0.range).contains("Title") })
    #expect(plan.runs.contains { $0.style == .heading(2) && ns.substring(with: $0.range).contains("Nested") })
    #expect(plan.runs.contains { $0.style == .emphasis && ns.substring(with: $0.range).contains("word") })
    #expect(plan.runs.contains { $0.style == .code && ns.substring(with: $0.range).contains("🦊") })
}
