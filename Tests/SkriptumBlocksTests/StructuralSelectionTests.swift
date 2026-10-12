import Foundation
import Testing
import SkriptumCore
@testable import SkriptumBlocks

@Test(arguments: ["# Foo", "- Foo", "> Foo", "- [ ] Foo", "# Café e\u{301} 🦊"])
func structuralChangeRetainsTheNativeFramesSelectedText(_ typed: String) throws {
    var frame = BlockInputFrame(source: "Text\n\n")
    let proposed = try #require(frame.proposedSource(text: typed, canonical: frame.source))
    frame.accept(text: typed, source: proposed)
    let word = typed.contains("Foo") ? "Foo" : "Café e\u{301} 🦊"
    let bodyRange = (frame.text as NSString).range(of: word)
    let sourceRange = frame.sourceSelection(bodyRange, text: frame.text)
    let active = Block(markdown: frame.source), other = Block(markdown: "Andere Seite\n\n")
    let before = [active, other], after = [other, active]
    let moved = try #require(BlockSelectionUpdate.sourceRange(previous: before, accepted: after, activeID: active.id,
        sourceSelection: sourceRange, bodySelection: bodyRange))
    let actual = (after.map(\.markdown).joined() as NSString).substring(with: moved)
    #expect(actual.utf8.elementsEqual(word.utf8))
    #expect(moved == NSRange(location: other.markdown.utf16.count + sourceRange.location, length: sourceRange.length))
    let duplicated = [active, Block(markdown: active.markdown), other]
    let retained = try #require(BlockSelectionUpdate.sourceRange(previous: before, accepted: duplicated, activeID: active.id,
        sourceSelection: sourceRange, bodySelection: bodyRange))
    #expect(retained == sourceRange)
}

@Test func structuralSelectionDoesNotRetainRemovedIdentityOrChangedBytes() throws {
    let active = Block(markdown: "# Café e\u{301}\n\n")
    let other = Block(markdown: "Other\n\n")
    let old = [other, active]
    let prior = NSRange(location: other.markdown.utf16.count + 7, length: 2)
    #expect(BlockSelectionUpdate.sourceRange(previous: old, accepted: [other], activeID: active.id,
        sourceSelection: prior, bodySelection: NSRange(location: 0, length: 1)) == nil)
    var normalized = active; normalized.markdown = active.markdown.precomposedStringWithCanonicalMapping
    #expect(normalized.markdown == active.markdown)
    #expect(!normalized.markdown.utf8.elementsEqual(active.markdown.utf8))
    let fallback = try #require(BlockSelectionUpdate.sourceRange(previous: old, accepted: [normalized, other], activeID: active.id,
        sourceSelection: prior, bodySelection: NSRange(location: 0, length: 1)))
    #expect(fallback == NSRange(location: 2, length: 1))
}

@Test func structuralSelectionRetainsSourceCaretAtBlockEndAndFallsBackForCrossBlockRange() throws {
    let active = Block(markdown: "# Heading\n\n"), other = Block(markdown: "Other\n\n")
    let old = [active, other], accepted = [other, active]
    let end = NSRange(location: active.markdown.utf16.count, length: 0)
    let moved = try #require(BlockSelectionUpdate.sourceRange(previous: old, accepted: accepted, activeID: active.id,
        sourceSelection: end, bodySelection: NSRange(location: 0, length: 0)))
    #expect(moved == NSRange(location: other.markdown.utf16.count + end.location, length: 0))
    let cross = try #require(BlockSelectionUpdate.sourceRange(previous: old, accepted: accepted, activeID: active.id,
        sourceSelection: NSRange(location: 0, length: active.markdown.utf16.count + 1), bodySelection: NSRange(location: 0, length: 1)))
    #expect(cross == NSRange(location: other.markdown.utf16.count + 2, length: 1))
}


#if canImport(AppKit)
import SwiftUI

@MainActor @Test func recreatedNativeFrameUsesSourceSelectionInsteadOfOldBodyCoordinates() {
    let source = "# Foo\n\n"
    let row = BlockNativeEditor(text: .constant(BlockProjection(source).text),
        selection: .constant(NSRange(location: 2, length: 3)), kind: .heading, headingLevel: 1,
        selectionChanged: { _ in }, command: nil, commandHandled: { _, _ in },
        source: source, sourceChanged: { _ in true }, sourceProvider: { source },
        sourceSelectionRequest: NSRange(location: 2, length: 3))
    let coordinator = row.makeCoordinator()
    let range = coordinator.initialSelection()
    let visible = (coordinator.inputFrame.text as NSString).substring(with: range)
    #expect(visible == "Foo")
    #expect(range == NSRange(location: 0, length: 3))
}
#endif

@Test func actualDuplicatePreservesSelectionWhenSeparatingTheLastBlock() throws {
    var frame = BlockInputFrame(source: "")
    frame.accept(text: "# Foo", source: "# Foo")
    let active = Block(markdown: frame.source)
    let body = NSRange(location: 2, length: 3)
    let after = BlockEditing.duplicating([active], id: active.id)
    #expect(after[0].markdown == "# Foo\n\n")
    let range = try #require(BlockSelectionUpdate.sourceRange(previous: [active], accepted: after,
        activeID: active.id, sourceSelection: frame.sourceSelection(body, text: frame.text), bodySelection: body))
    #expect((after.map(\.markdown).joined() as NSString).substring(with: range) == "Foo")
}

#if canImport(AppKit)
import AppKit

@MainActor @Test func existingNativeFrameRetainsSelectionWhenDuplicateAddsSeparators() {
    let row = BlockNativeEditor(text: .constant("Foo"), selection: .constant(NSRange(location: 2, length: 3)),
        kind: .heading, headingLevel: 1, selectionChanged: { _ in }, command: nil,
        commandHandled: { _, _ in }, source: "# Foo\n\n", sourceChanged: { _ in true },
        sourceProvider: { "# Foo\n\n" }, sourceSelectionRequest: NSRange(location: 2, length: 3))
    let coordinator = row.makeCoordinator()
    coordinator.inputFrame = BlockInputFrame(source: "")
    coordinator.inputFrame.accept(text: "# Foo", source: "# Foo")
    let view = NSTextView()
    view.string = "# Foo"; view.setSelectedRange(NSRange(location: 2, length: 3))
    coordinator.presenting = true
    coordinator.synchronize(view)
    coordinator.presenting = false
    #expect(view.string == "Foo")
    #expect(view.selectedRange() == NSRange(location: 0, length: 3))
}
#endif
