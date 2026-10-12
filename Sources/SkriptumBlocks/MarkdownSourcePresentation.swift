import Foundation
import CoreGraphics
import Markdown

/// Attribute runs over unchanged source, never a reconstructed Markdown string.
public struct MarkdownSourcePresentation: Sendable {
    public enum Style: Equatable, Sendable { case heading(Int), code, strong, emphasis, marker }
    public struct Run: Equatable, Sendable { public let range: NSRange; public let style: Style }
    public let source: String
    public let runs: [Run]
    public init(source: String) throws {
        try Task.checkCancellation()
        self.source = source
        let bytes = Array(source.utf8)
        var starts = [0]
        for (i, byte) in bytes.enumerated() where byte == 10 { starts.append(i + 1) }
        func offset(_ location: SourceLocation) -> Int? {
            guard location.line > 0, location.line <= starts.count, location.column > 0 else { return nil }
            let start = starts[location.line - 1]
            let end = location.line < starts.count ? starts[location.line] : bytes.count
            guard location.column - 1 <= end - start else { return nil }
            return start + location.column - 1
        }
        let document = Document(parsing: source)
        var stack: [any Markup] = [document], raw: [(Int, Int, Style)] = [], endpoints = Set<Int>()
        while let node = stack.popLast() {
            try Task.checkCancellation()
            let style: Style?
            switch node {
            case let heading as Heading: style = .heading(heading.level)
            case is CodeBlock, is InlineCode, is Table: style = .code
            case is Strong: style = .strong
            case is Emphasis: style = .emphasis
            default: style = nil
            }
            if let range = node.range, let lower = offset(range.lowerBound), let upper = offset(range.upperBound), lower < upper {
                if let style { raw.append((lower, upper, style)); endpoints.insert(lower); endpoints.insert(upper) }
                for (a, b) in Self.markerRanges(of: node, lower: lower, upper: upper, bytes: bytes) {
                    raw.append((a, b, .marker)); endpoints.insert(a); endpoints.insert(b)
                }
            }
            stack.append(contentsOf: Array(node.children).reversed())
        }
        // Map only requested scalar boundaries in one pass, avoiding repeated
        // prefix scans for a long paragraph with many inline nodes.
        var mapped: [Int: Int] = [:], utf8 = 0, utf16 = 0
        for scalar in source.unicodeScalars {
            if endpoints.contains(utf8) { mapped[utf8] = utf16 }
            let v = scalar.value
            utf8 += v < 0x80 ? 1 : v < 0x800 ? 2 : v < 0x10000 ? 3 : 4
            utf16 += v < 0x10000 ? 1 : 2
        }
        if endpoints.contains(utf8) { mapped[utf8] = utf16 }
        try Task.checkCancellation()
        runs = raw.compactMap { lower, upper, style in
            guard let a = mapped[lower], let b = mapped[upper], a < b else { return nil }
            return Run(range: NSRange(location: a, length: b - a), style: style)
        }
    }
}
extension MarkdownSourcePresentation {
    /// Byte ranges of syntax characters (delimiters, `#`, `>`, list bullets, fences) inside a node.
    static func markerRanges(of node: any Markup, lower: Int, upper: Int, bytes: [UInt8]) -> [(Int, Int)] {
        func run(_ from: Int, _ set: [UInt8]) -> Int {
            var i = from
            while i < upper, set.contains(bytes[i]) { i += 1 }
            return i - from
        }
        switch node {
        case is Strong:
            let n = min(2, (upper - lower) / 2)
            guard n > 0, bytes[lower] == 42 || bytes[lower] == 95 else { return [] }
            return [(lower, lower + n), (upper - n, upper)]
        case is Emphasis:
            guard upper - lower >= 2, bytes[lower] == 42 || bytes[lower] == 95 else { return [] }
            return [(lower, lower + 1), (upper - 1, upper)]
        case is InlineCode:
            let n = run(lower, [96])
            guard n > 0, upper - lower > 2 * n else { return [] }
            return [(lower, lower + n), (upper - n, upper)]
        case is Heading:
            guard bytes[lower] == 35 else { return [] }
            let hashes = run(lower, [35])
            return [(lower, lower + hashes + run(lower + hashes, [32, 9]))]
        case is BlockQuote:
            var result: [(Int, Int)] = [], i = lower
            while i < upper {
                var j = i + run(i, [32])
                if j < upper, bytes[j] == 62 { result.append((j, j + 1)); j += 1 }
                while j < upper, bytes[j] != 10 { j += 1 }
                i = j + 1
            }
            return result
        case is ListItem:
            var j = lower + run(lower, [32])
            let start = j
            while j < upper, bytes[j] != 32, bytes[j] != 10, j - start < 10 { j += 1 }
            return j > start ? [(start, j)] : []
        case is CodeBlock:
            let fence = bytes[lower] == 96 || bytes[lower] == 126 ? bytes[lower] : 0
            guard fence != 0 else { return [] }
            var end = lower
            while end < upper, bytes[end] != 10 { end += 1 }
            var result = [(lower, end)]
            var close = upper
            while close > end, bytes[close - 1] == 10 || bytes[close - 1] == 13 { close -= 1 }
            var lastStart = close
            while lastStart > end + 1, bytes[lastStart - 1] != 10 { lastStart -= 1 }
            if lastStart > end, lastStart < close, bytes[lastStart] == fence { result.append((lastStart, close)) }
            return result
        default: return []
        }
    }
}

/// Serial work prevents obsolete large parses from executing concurrently.
actor MarkdownPresentationWorker {
    static let shared = MarkdownPresentationWorker()
    func make(_ source: String) throws -> MarkdownSourcePresentation {
        try Task.checkCancellation()
        return try MarkdownSourcePresentation(source: source)
    }
}

/// Attribute-only styling over unchanged text. The string is never rebuilt.
enum MarkdownInlineStyling {
    /// Emphasis first, syntax markers last so a dimmed marker wins over a bold run.
    static func apply(_ runs: [MarkdownSourcePresentation.Run], to storage: NSMutableAttributedString,
                      attributes: (MarkdownSourcePresentation.Style, [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any]?) {
        let length = storage.length
        let ordered = runs.filter { $0.style != .marker } + runs.filter { $0.style == .marker }
        for run in ordered where run.range.location >= 0 && NSMaxRange(run.range) <= length {
            var pieces: [(NSRange, [NSAttributedString.Key: Any])] = []
            storage.enumerateAttributes(in: run.range, options: []) { existing, range, _ in pieces.append((range, existing)) }
            for (range, existing) in pieces {
                if let changed = attributes(run.style, existing) { storage.addAttributes(changed, range: range) }
            }
        }
    }
}

/// Pure geometry for keeping the caret above the keyboard and its accessory bar.
public enum CaretVisibility {
    /// Positive: scroll content up (offset grows). Negative: caret hides under the top edge.
    public static func offsetDelta(caret: CGRect, visibleTop: CGFloat, obscuredTop: CGFloat, margin: CGFloat) -> CGFloat {
        if caret.maxY + margin > obscuredTop { return caret.maxY + margin - obscuredTop }
        if caret.minY - margin < visibleTop { return caret.minY - margin - visibleTop }
        return 0
    }
    public static func clampedOffset(current: CGFloat, delta: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(current + delta, minimum), max(minimum, maximum))
    }
    /// The accessory bar is part of the reported keyboard frame on some systems and not on others.
    public static func obscuredTop(keyboardTop: CGFloat?, accessoryTop: CGFloat?) -> CGFloat? {
        switch (keyboardTop, accessoryTop) {
        case let (k?, a?): min(k, a)
        case let (k?, nil): k
        case let (nil, a?): a
        default: nil
        }
    }
}
