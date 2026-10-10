import Foundation
import Markdown

/// Attribute runs over unchanged source, never a reconstructed Markdown string.
public struct MarkdownSourcePresentation: Sendable {
    public enum Style: Equatable, Sendable { case heading(Int), code, strong, emphasis }
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
            if let style, let range = node.range, let lower = offset(range.lowerBound), let upper = offset(range.upperBound), lower < upper {
                raw.append((lower, upper, style)); endpoints.insert(lower); endpoints.insert(upper)
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
/// Serial work prevents obsolete large parses from executing concurrently.
actor MarkdownPresentationWorker {
    static let shared = MarkdownPresentationWorker()
    func make(_ source: String) throws -> MarkdownSourcePresentation {
        try Task.checkCancellation()
        return try MarkdownSourcePresentation(source: source)
    }
}
