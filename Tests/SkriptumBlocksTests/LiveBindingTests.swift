#if canImport(AppKit)
import Foundation
import AppKit
import SwiftUI
import Testing
import SkriptumCore
@testable import SkriptumBlocks

@MainActor struct LiveBindingTests {
    @MainActor private final class FixtureBox {
        var block: Block
        var selection = NSRange(location: 0, length: 0)
        init(source: String) { block = Block(markdown: source) }
        func write(_ text: String) { block.markdown = BlockProjection(block.markdown).replacingText(text) }
    }
    @Test func constructedRowReadsCurrentCanonicalSourceDuringNativeSynchronization() {
        let initial = "body😀 e\u{301}\r\n\r\n", box = FixtureBox(source: "body😀 e\u{301}\r\n\r\n")
        let id = box.block.id
        let body = BlockEditorBinding.text(readSource: { box.block.markdown }, writeText: { box.write($0) })
        let selection = Binding(get: { box.selection }, set: { box.selection = $0 })
        let row = BlockNativeEditor(text: body, selection: selection, kind: .paragraph, headingLevel: 0,
            selectionChanged: { box.selection = $0 }, command: nil, commandHandled: { _, _ in }, source: initial,
            sourceChanged: { box.block.markdown = $0; return true }, sourceProvider: { box.block.markdown })
        let coordinator = row.makeCoordinator()
        let view = NSTextView(); view.isRichText = false; view.string = body.wrappedValue
        let edited = view.string + "🦉!"
        view.string = edited
        let caret = NSRange(location: edited.utf16.count, length: 0)
        view.setSelectedRange(caret)
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
        #expect(box.block.id == id)
        #expect(box.block.markdown.utf8.elementsEqual((edited + "\r\n\r\n").utf8))
        coordinator.synchronize(view)
        #expect(view.string.utf8.elementsEqual(edited.utf8))
        #expect(view.selectedRange() == caret)
        #expect(box.block.id == id)
        // Legitimate external restoration must apply even though this row was
        // constructed before typing and its canonical bytes match that baseline.
        box.block.markdown = initial
        box.selection = NSRange(location: 2, length: 1)
        coordinator.synchronize(view)
        #expect(view.string.utf8.elementsEqual(BlockProjection(initial).text.utf8))
        #expect(view.selectedRange() == box.selection)
        #expect(box.block.id == id)
        #expect(box.block.markdown.utf8.elementsEqual(initial.utf8))
    }
}
#endif
