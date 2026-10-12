import SwiftUI

/// The native buffer may receive several edits before SwiftUI renders again.
/// Keep its syntax basis until an external change or explicit style operation.
struct BlockInputFrame: Sendable {
    private(set) var source: String
    private(set) var text: String
    private(set) var projection: BlockProjection
    init(source: String) {
        self.source = source; projection = BlockProjection(source); text = projection.text
    }
    func proposedSource(text: String, canonical: String) -> String? {
        guard source.utf8.elementsEqual(canonical.utf8) else { return nil }
        return projection.replacingText(text)
    }
    func draftSource(text: String) -> String { projection.replacingText(text) }
    mutating func accept(text: String, source: String) { self.text = text; self.source = source }
    mutating func rebase(source: String) { self = Self(source: source) }
    func bodySelection(forSource range: NSRange) -> NSRange {
        let count = source.utf16.count
        let start = min(count, max(0, range.location))
        let length = min(max(0, range.length), count - start)
        let bodyStart = projection.bodyOffset(forSourceOffset: start, editingText: text)
        let bodyEnd = projection.bodyOffset(forSourceOffset: start + length, editingText: text)
        return NSRange(location: bodyStart, length: max(0, bodyEnd - bodyStart))
    }
    func sourceSelection(_ range: NSRange, text: String) -> NSRange {
        let start = projection.sourceOffset(for: range.location, editingText: text)
        let end = projection.sourceOffset(for: range.location + range.length, editingText: text)
        return NSRange(location: start, length: max(0, end - start))
    }
}

@MainActor enum BlockEditorBinding {
    static func text(readSource: @escaping () -> String, writeText: @escaping (String) -> Void) -> Binding<String> {
        // Read the current canonical block for every synchronization; the row
        // value may have been constructed before a successful native keystroke.
        return Binding(get: { BlockProjection(readSource()).text }, set: writeText)
    }
}
