#if canImport(AppKit)
import Foundation
import AppKit
import SwiftUI
import Testing
import SkriptumCore
@testable import SkriptumBlocks

@MainActor struct LiveBindingTests {
    @MainActor private final class UndoView: NSTextView {
        let ownedUndo = UndoManager()
        override var undoManager: UndoManager? { ownedUndo }
    }
    @Test func explicitStyleUndoRedoRebasesFrameAndRejectsForeignInverse() {
        let original = "Original e\u{301} 🦊\r\n\r\n", box = FixtureBox(source: original)
        var rejected: [String] = []
        let row = BlockNativeEditor(text: BlockEditorBinding.text(readSource: { box.block.markdown }, writeText: { box.write($0) }),
            selection: Binding(get: { box.selection }, set: { box.selection = $0 }), kind: .paragraph, headingLevel: 0,
            selectionChanged: { box.selection = $0 }, command: nil, commandHandled: { _, _ in }, source: original,
            sourceChanged: { box.block.markdown = $0; return true }, sourceProvider: { box.block.markdown },
            sourceRejected: { rejected.append($0); return true })
        let coordinator = row.makeCoordinator(), view = UndoView()
        view.isRichText = false; view.string = BlockProjection(original).text
        let command = BlockEditorCommand(prefix: "## ", suffix: "")
        view.ownedUndo.beginUndoGrouping()
        #expect(coordinator.applyStyle(command, to: view))
        view.ownedUndo.endUndoGrouping()
        let styled = box.block.markdown
        #expect(styled.utf8.elementsEqual(("## " + original).utf8))
        view.ownedUndo.undo()
        #expect(box.block.markdown.utf8.elementsEqual(original.utf8))
        view.ownedUndo.redo()
        #expect(box.block.markdown.utf8.elementsEqual(styled.utf8))
        box.block.markdown = "Foreign source 🦊"
        view.ownedUndo.undo()
        #expect(box.block.markdown == "Foreign source 🦊")
        #expect(rejected.last?.utf8.elementsEqual(original.utf8) == true)
    }
    @Test(arguments: [1, 2, 64])
    func typedMarkdownSurvivesDifferentRenderInterleavings(renderEvery: Int) {
        let box = FixtureBox(source: "")
        let body = BlockEditorBinding.text(readSource: { box.block.markdown }, writeText: { box.write($0) })
        let row = BlockNativeEditor(text: body, selection: Binding(get: { box.selection }, set: { box.selection = $0 }),
            kind: .paragraph, headingLevel: 0, selectionChanged: { box.selection = $0 }, command: nil,
            commandHandled: { _, _ in }, source: "", sourceChanged: { box.block.markdown = $0; return true },
            sourceProvider: { box.block.markdown })
        let coordinator = row.makeCoordinator(), view = NSTextView()
        view.isRichText = false; view.string = ""
        let input = "# QA Kapitel\n\nCafé e\u{301} 🦊 — **Fett**.\n"
        for (index, character) in input.enumerated() {
            let caret = view.selectedRange().location
            var next = view.string
            next.insert(character, at: String.Index(utf16Offset: caret, in: next))
            view.string = next
            view.setSelectedRange(NSRange(location: caret + String(character).utf16.count, length: 0))
            coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
            if (index + 1).isMultiple(of: renderEvery) { coordinator.synchronize(view) }
        }
        coordinator.synchronize(view)
        #expect(box.block.markdown.utf8.elementsEqual(input.utf8))
        #expect(view.string.utf8.elementsEqual(input.utf8))
        #expect(view.selectedRange().location == input.utf16.count)
    }

    @MainActor private final class FixtureBox {
        var block: Block
        var selection = NSRange(location: 0, length: 0)
        init(source: String) { block = Block(markdown: source) }
        func write(_ text: String) { block.markdown = BlockProjection(block.markdown).replacingText(text) }
    }
    @Test func foreignSourceNeverReceivesAnOldNativeDraftAndFailedRecoveryKeepsBuffer() {
        let box = FixtureBox(source: "# Original\r\n\r\n")
        var writes = 0, drafts: [String] = [], canRecover = false
        let row = BlockNativeEditor(text: BlockEditorBinding.text(readSource: { box.block.markdown }, writeText: { box.write($0) }),
            selection: Binding(get: { box.selection }, set: { box.selection = $0 }), kind: .heading, headingLevel: 1,
            selectionChanged: { box.selection = $0 }, command: nil, commandHandled: { _, _ in }, source: box.block.markdown,
            sourceChanged: { writes += 1; box.block.markdown = $0; return true }, sourceProvider: { box.block.markdown },
            sourceRejected: { drafts.append($0); return canRecover })
        let coordinator = row.makeCoordinator(), view = NSTextView()
        view.isRichText = false; view.string = "Original"
        box.block.markdown = "# Foreign 🦊\r\n\r\n"
        view.string = "Original e\u{301} draft"; view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
        coordinator.synchronize(view)
        #expect(writes == 0)
        #expect(box.block.markdown == "# Foreign 🦊\r\n\r\n")
        #expect(view.string.utf8.elementsEqual("Original e\u{301} draft".utf8))
        #expect(drafts.allSatisfy { $0.utf8.elementsEqual("# Original e\u{301} draft\r\n\r\n".utf8) })
        #expect(!drafts.isEmpty)
        canRecover = true
        coordinator.synchronize(view)
        #expect(view.string == "Foreign 🦊")
        #expect(writes == 0)
    }

    @Test func growingProjectedHeadingKeepsCRLFAndSourceSelectionRequests() {
        let box = FixtureBox(source: "# Original\r\n\r\n")
        var sourceRange = NSRange(location: 0, length: 0)
        var row = BlockNativeEditor(text: BlockEditorBinding.text(readSource: { box.block.markdown }, writeText: { box.write($0) }),
            selection: Binding(get: { box.selection }, set: { box.selection = $0 }), kind: .heading, headingLevel: 1,
            selectionChanged: { box.selection = $0 }, command: nil, commandHandled: { _, _ in }, source: box.block.markdown,
            sourceChanged: { box.block.markdown = $0; return true }, sourceProvider: { box.block.markdown },
            sourceSelectionChanged: { sourceRange = $0 })
        let coordinator = row.makeCoordinator(), view = NSTextView()
        view.isRichText = false; view.string = "Original 🦊 e\u{301}"
        let caret = NSRange(location: view.string.utf16.count, length: 0)
        view.setSelectedRange(caret)
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
        coordinator.synchronize(view)
        #expect(box.block.markdown.utf8.elementsEqual(("# " + view.string + "\r\n\r\n").utf8))
        #expect(sourceRange == NSRange(location: caret.location + 2, length: 0))
        row.sourceSelectionRequest = (box.block.markdown as NSString).range(of: "🦊")
        row.selectionRequestGeneration = 1; coordinator.parent = row
        coordinator.synchronize(view)
        #expect(view.selectedRange() == (view.string as NSString).range(of: "🦊"))
    }
    @Test func constructedRowReadsCurrentCanonicalSourceDuringNativeSynchronization() {
        let initial = "body😀 e\u{301}\r\n\r\n", box = FixtureBox(source: "body😀 e\u{301}\r\n\r\n")
        let id = box.block.id
        let body = BlockEditorBinding.text(readSource: { box.block.markdown }, writeText: { box.write($0) })
        let selection = Binding(get: { box.selection }, set: { box.selection = $0 })
        var row = BlockNativeEditor(text: body, selection: selection, kind: .paragraph, headingLevel: 0,
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
        // A delayed native selection echo must not move the actual caret.
        box.selection = NSRange(location: 0, length: 0)
        coordinator.synchronize(view)
        #expect(view.selectedRange() == caret)
        // Legitimate external restoration with explicit navigation must apply even though this row was
        // constructed before typing and its canonical bytes match that baseline.
        box.block.markdown = initial
        box.selection = NSRange(location: 2, length: 1)
        row.selectionRequestGeneration = 1
        coordinator.parent = row
        coordinator.synchronize(view)
        #expect(view.string.utf8.elementsEqual(BlockProjection(initial).text.utf8))
        #expect(view.selectedRange() == box.selection)
        #expect(box.block.id == id)
        #expect(box.block.markdown.utf8.elementsEqual(initial.utf8))
    }
}
#endif
