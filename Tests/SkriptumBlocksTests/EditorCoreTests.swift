import Foundation
import CoreGraphics
import Testing
@testable import SkriptumBlocks

private let witness = "# QA Kapitel\n\nCafé e\u{301} 🦊 — **Fett**.\n"

private func markers(_ source: String) throws -> [String] {
    let plan = try MarkdownSourcePresentation(source: source)
    let ns = source as NSString
    return plan.runs.filter { $0.style == .marker }.map { ns.substring(with: $0.range) }
}

@Test func caretBelowKeyboardScrollsContentUpByOverlapAndMargin() {
    let caret = CGRect(x: 20, y: 600, width: 2, height: 20)
    #expect(CaretVisibility.offsetDelta(caret: caret, visibleTop: 100, obscuredTop: 580, margin: 12) == 52)
}
@Test func caretAboveKeyboardNeedsNoScroll() {
    let caret = CGRect(x: 20, y: 300, width: 2, height: 20)
    #expect(CaretVisibility.offsetDelta(caret: caret, visibleTop: 100, obscuredTop: 580, margin: 12) == 0)
}
@Test func caretUnderTopEdgeScrollsBackDown() {
    let caret = CGRect(x: 20, y: 90, width: 2, height: 20)
    #expect(CaretVisibility.offsetDelta(caret: caret, visibleTop: 100, obscuredTop: 580, margin: 12) == -22)
}
@Test func caretOffsetIsClampedToScrollableRange() {
    #expect(CaretVisibility.clampedOffset(current: 10, delta: 500, minimum: 0, maximum: 120) == 120)
    #expect(CaretVisibility.clampedOffset(current: 10, delta: -50, minimum: 0, maximum: 120) == 0)
    #expect(CaretVisibility.clampedOffset(current: 10, delta: 5, minimum: 0, maximum: -4) == 0)
}
@Test func obscuredTopTakesTheHigherEdgeWhetherOrNotKeyboardIncludesAccessory() {
    #expect(CaretVisibility.obscuredTop(keyboardTop: 560, accessoryTop: 560) == 560)
    #expect(CaretVisibility.obscuredTop(keyboardTop: 604, accessoryTop: 560) == 560)
    #expect(CaretVisibility.obscuredTop(keyboardTop: 560, accessoryTop: nil) == 560)
    #expect(CaretVisibility.obscuredTop(keyboardTop: nil, accessoryTop: nil) == nil)
}

@Test func inputFrameStyleFollowsCurrentFirstLineKind() {
    var frame = BlockInputFrame(source: "Satz")
    #expect(frame.styleKind == .paragraph)
    frame.accept(text: "## Satz", source: "## Satz")
    #expect(frame.styleKind == .heading && frame.styleHeadingLevel == 2)
    frame.accept(text: "Satz", source: "Satz")
    #expect(frame.styleKind == .paragraph && frame.styleHeadingLevel == 0)
}
@Test func inputFrameKeepsSyntaxBasisForOffsetMappingWhileStyleMoves() {
    var frame = BlockInputFrame(source: "Satz")
    frame.accept(text: "# Satz", source: "# Satz")
    #expect(frame.projection.kind == .paragraph)
    #expect(frame.styleKind == .heading)
}
@Test func headingFollowedByBodyLineKeepsHeadingRoleOnFirstLine() {
    var frame = BlockInputFrame(source: "# Titel\n")
    frame.accept(text: "Titel\nFließtext", source: "# Titel\n# Fließtext")
    #expect(frame.styleKind == .heading && frame.styleHeadingLevel == 1)
}

@Test func markerRunsCoverEmphasisCodeHeadingQuoteListAndFence() throws {
    #expect(try markers(witness) == ["# ", "**", "**"])
    #expect(try markers("a *b* and `c` and ``d``\n") == ["*", "*", "`", "`", "``", "``"])
    #expect(try markers("> zitat\n> zwei\n") == [">", ">"])
    #expect(try markers("- eins\n- zwei\n") == ["-", "-"])
    #expect(try markers("```swift\nlet x = 1\n```\n") == ["```swift", "```"])
    #expect(try markers("### Drei") == ["### "])
}

@Test func inlineStylingNeverChangesTheStringBytes() throws {
    for source in [witness, "a *b* **c** `d`\n> q\n", "😀 **e\u{301}**"] {
        let before = Array(source.utf8)
        let plan = try MarkdownSourcePresentation(source: source)
        let storage = NSMutableAttributedString(string: source)
        let key = NSAttributedString.Key("role")
        MarkdownInlineStyling.apply(plan.runs, to: storage) { style, _ in [key: "\(style)"] }
        #expect(Array(storage.string.utf8) == before)
        #expect(plan.source.utf8.elementsEqual(source.utf8))
    }
    #expect(witness.utf8.count == 43)
}
@Test func inlineStylingMarksMarkersLastSoTheyWinOverEmphasis() throws {
    let source = "x **b** y"
    let plan = try MarkdownSourcePresentation(source: source)
    let storage = NSMutableAttributedString(string: source)
    let key = NSAttributedString.Key("role")
    MarkdownInlineStyling.apply(plan.runs, to: storage) { style, _ in [key: style == .marker ? "marker" : "strong"] }
    #expect(storage.attribute(key, at: 2, effectiveRange: nil) as? String == "marker")
    #expect(storage.attribute(key, at: 4, effectiveRange: nil) as? String == "strong")
    #expect(storage.attribute(key, at: 0, effectiveRange: nil) == nil)
}

@Test func headingCommandCyclesThroughLevelsAndBackToBody() {
    #expect(BlockEditorCommand.heading(after: 0).prefix == "# ")
    #expect(BlockEditorCommand.heading(after: 1).prefix == "## ")
    #expect(BlockEditorCommand.heading(after: 2).prefix == "### ")
    #expect(BlockEditorCommand.heading(after: 3).prefix == "")
    #expect((0...3).allSatisfy { BlockEditorCommand.heading(after: $0).isLineStyle })
}
@Test func headingCommandRewritesOnlyTheLinePrefix() throws {
    let command = BlockEditorCommand.heading(after: 1)
    let edit = try #require(MarkdownLineStyling.applying(command, to: "# Titel\n", selection: NSRange(location: 2, length: 0)))
    #expect(edit.source == "## Titel\n")
    let removed = try #require(MarkdownLineStyling.applying(.heading(after: 3), to: "### Titel\n", selection: NSRange(location: 4, length: 0)))
    #expect(removed.source == "Titel\n")
}
@Test func linkCommandWrapsSelectionAndTargetsThePlaceholder() throws {
    let edit = try #require(BlockCommandEditing.applying(.link, to: "ein Wort hier", selection: NSRange(location: 4, length: 4)))
    #expect(edit.replacement == "[Wort](https://)")
    let target = BlockEditorCommand.linkURLSelection(afterReplacing: edit.replacementRange)
    #expect((edit.text as NSString).substring(with: target) == "https://")
}
@Test func boldAndItalicCommandsAreFreshEachTime() {
    #expect(BlockEditorCommand.bold.id != BlockEditorCommand.bold.id)
    #expect(BlockEditorCommand.bold.prefix == "**" && BlockEditorCommand.italic.suffix == "*")
}
