import Foundation
#if canImport(SkriptumCore)
import SkriptumCore
#endif

public struct BlockEditorCommand: Equatable, Sendable {
    public let id: UUID
    public let prefix: String
    public let suffix: String
    public init(id: UUID = UUID(), prefix: String, suffix: String) {
        self.id = id; self.prefix = prefix; self.suffix = suffix
    }
    public var isLineStyle: Bool { suffix.isEmpty && (prefix == "## " || prefix == "- ") }
}

public struct BlockLineStyleEdit: Equatable, Sendable {
    public let source: String
    public let selection: NSRange
    public let undoSource: String
    public let undoSelection: NSRange
}

public enum MarkdownLineStyling {
    public static func applying(_ command: BlockEditorCommand, to source: String, selection: NSRange) -> BlockLineStyleEdit? {
        guard command.isLineStyle, selection.location >= 0, selection.length >= 0,
            selection.location <= source.utf16.count, selection.length <= source.utf16.count - selection.location,
            BlockCommandEditing.isScalarBoundary(selection.location, in: source),
            BlockCommandEditing.isScalarBoundary(selection.location + selection.length, in: source) else { return nil }
        struct Line { var body: String; let ending: String; let start: Int }
        let bytes = Array(source.utf8)
        var lines: [Line] = [], position = 0, sourcePosition = 0
        while position < bytes.count {
            let end = bytes[position...].firstIndex(of: 10) ?? bytes.count
            let cr = end > position && bytes[end - 1] == 13
            let body = String(decoding: bytes[position..<(cr ? end - 1 : end)], as: UTF8.self)
            let ending = (cr ? "\r" : "") + (end < bytes.count ? "\n" : "")
            lines.append(Line(body: body, ending: ending, start: sourcePosition))
            sourcePosition += body.utf16.count + ending.utf16.count
            position = end < bytes.count ? end + 1 : end
        }
        if lines.isEmpty || source.hasSuffix("\n") { lines.append(Line(body: "", ending: "", start: sourcePosition)) }
        let lastSelected = selection.location + max(0, selection.length - 1)
        var fence: Character?, fenceLength = 0
        var patches: [(start: Int, oldLength: Int, newLength: Int)] = []
        for index in lines.indices {
            let line = lines[index], trimmed = line.body.trimmingCharacters(in: .whitespaces)
            let marker = trimmed.first
            let run = marker == "`" || marker == "~" ? trimmed.prefix(while: { $0 == marker }).count : 0
            let insideFence = fence != nil
            let fenceLine = run >= 3
            if fenceLine {
                if fence == nil { fence = marker; fenceLength = run }
                else if fence == marker && run >= fenceLength && trimmed.dropFirst(run).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
            }
            let end = line.start + line.body.utf16.count + line.ending.utf16.count
            let selected = line.start <= lastSelected && (end > selection.location || (line.start == source.utf16.count && selection.location == line.start))
            guard selected else { continue }
            guard !insideFence, !fenceLine, !trimmed.hasPrefix("!["), !trimmed.hasPrefix("|") else { return nil }
            if selection.length > 0 && trimmed.isEmpty { continue }
            let indentation = String(line.body.prefix(while: { $0 == " " || $0 == "\t" }))
            let content = String(line.body.dropFirst(indentation.count))
            let pattern = #"^(?:#{1,6}[ \t]+|(?:[-+*]|[0-9]+[.)])[ \t]+(?:\[[ xX]\][ \t]+)?|>[ \t]?)"#
            let existing = content.range(of: pattern, options: .regularExpression).map { String(content[$0]) } ?? ""
            guard indentation.count < 4 && !indentation.contains("\t") || !existing.isEmpty else { return nil }
            let oldPrefix = indentation + existing, newPrefix = indentation + command.prefix
            lines[index].body = newPrefix + String(content.dropFirst(existing.count))
            patches.append((line.start, oldPrefix.utf16.count, newPrefix.utf16.count))
        }
        guard !patches.isEmpty else { return nil }
        func map(_ offset: Int) -> Int {
            var delta = 0
            for patch in patches {
                if offset < patch.start { break }
                if offset <= patch.start + patch.oldLength { return patch.start + delta + patch.newLength }
                delta += patch.newLength - patch.oldLength
            }
            return offset + delta
        }
        let start = map(selection.location), end = map(selection.location + selection.length)
        return BlockLineStyleEdit(source: lines.map { $0.body + $0.ending }.joined(), selection: NSRange(location: start, length: max(0, end - start)), undoSource: source, undoSelection: selection)
    }
}

public struct BlockCommandGate: Sendable {
    private var lastID: UUID?
    public init() {}
    public mutating func claim(_ id: UUID) -> Bool {
        guard lastID != id else { return false }
        lastID = id; return true
    }
}

public struct BlockInlineEdit: Equatable, Sendable {
    public let text: String
    public let selection: NSRange
    public let replacement: String
    public let replacementRange: NSRange
}

public struct BlockCaretTarget: Equatable, Sendable {
    public let blockID: UUID
    public let selection: NSRange
}

public enum BlockCommandEditing {
    public static func applying(_ command: BlockEditorCommand, to text: String, selection: NSRange) -> BlockInlineEdit? {
        guard selection.location >= 0, selection.length >= 0,
            selection.location <= text.utf16.count, selection.length <= text.utf16.count - selection.location,
            isScalarBoundary(selection.location, in: text), isScalarBoundary(selection.location + selection.length, in: text),
            let range = Range(selection, in: text) else { return nil }
        let replacement = command.prefix + String(text[range]) + command.suffix
        var changed = text
        changed.replaceSubrange(range, with: replacement)
        return BlockInlineEdit(text: changed,
            selection: NSRange(location: selection.location + command.prefix.utf16.count, length: selection.length),
            replacement: replacement, replacementRange: selection)
    }

    public static func caretTarget(in blocks: [Block], sourceOffset: Int) -> BlockCaretTarget? {
        guard !blocks.isEmpty else { return nil }
        let total = blocks.reduce(0) { $0 + $1.markdown.utf16.count }
        let requested = min(max(0, sourceOffset), total)
        var start = 0
        for (index, block) in blocks.enumerated() {
            let end = start + block.markdown.utf16.count
            if requested < end || index == blocks.count - 1 {
                let projection = BlockProjection(block.markdown)
                var offset = projection.bodyOffset(forSourceOffset: requested - start)
                // A caret must never split a UTF-16 surrogate pair.
                while offset > 0, !isScalarBoundary(offset, in: projection.text) { offset -= 1 }
                return BlockCaretTarget(blockID: block.id, selection: NSRange(location: offset, length: 0))
            }
            start = end
        }
        return nil
    }

    fileprivate static func isScalarBoundary(_ offset: Int, in text: String) -> Bool {
        let utf16 = text as NSString
        guard offset > 0, offset < utf16.length else { return true }
        let previous = utf16.character(at: offset - 1), next = utf16.character(at: offset)
        return !((0xD800...0xDBFF).contains(previous) && (0xDC00...0xDFFF).contains(next))
    }
}
