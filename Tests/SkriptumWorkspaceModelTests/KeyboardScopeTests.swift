import Foundation
import Testing
@testable import SkriptumWorkspaceModel

struct KeyboardScopeTests {
    private let window = CGRect(x: 0, y: 0, width: 402, height: 874)
    @Test func dockedKeyboardOverlapsFromItsTopEdge() {
        #expect(KeyboardFrameMath.overlap(endFrame: CGRect(x: 0, y: 600, width: 402, height: 274), windowBounds: window) == 274)
    }
    @Test func offscreenOrNullFramesCountAsHidden() {
        #expect(KeyboardFrameMath.overlap(endFrame: CGRect(x: 0, y: 874, width: 402, height: 274), windowBounds: window) == 0)
        #expect(KeyboardFrameMath.overlap(endFrame: .null, windowBounds: window) == 0)
        #expect(KeyboardFrameMath.overlap(endFrame: CGRect(x: 0, y: 600, width: 402, height: 274), windowBounds: .null) == 0)
    }
    @Test func frameBelowWindowBottomIsClipped() {
        #expect(KeyboardFrameMath.overlap(endFrame: CGRect(x: 0, y: 800, width: 402, height: 274), windowBounds: window) == 74)
    }
    @Test func scopePrefersSelectionThenBlockThenPage() {
        let selection = NSRange(location: 4, length: 3), block = NSRange(location: 0, length: 20)
        #expect(EditorTextScope.resolve(selection: selection, activeBlock: block, utf16Length: 50) == .init(kind: .selection, range: selection))
        #expect(EditorTextScope.resolve(selection: NSRange(location: 5, length: 0), activeBlock: block, utf16Length: 50) == .init(kind: .block, range: block))
        #expect(EditorTextScope.resolve(selection: nil, activeBlock: nil, utf16Length: 50) == .page)
    }
    @Test func staleRangesBeyondTheTextFallBack() {
        let stale = NSRange(location: 40, length: 20)
        #expect(EditorTextScope.resolve(selection: stale, activeBlock: NSRange(location: 0, length: 10), utf16Length: 50).kind == .block)
        #expect(EditorTextScope.resolve(selection: stale, activeBlock: stale, utf16Length: 50) == .page)
        #expect(EditorTextScope.resolve(selection: NSRange(location: -1, length: 2), activeBlock: nil, utf16Length: 50) == .page)
    }
}
