import Foundation

/// Byte-sensitive input identity: canonically equivalent Unicode spellings can
/// have different UTF-16 scroll positions, so String's equality is insufficient.
public struct PageOutlineSource: Equatable, Sendable {
    public let markdown: String
    public init(_ markdown: String) { self.markdown = markdown }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.markdown.utf8.elementsEqual(rhs.markdown.utf8)
    }
}

/// Immutable navigation projection. Reading an outline never rewrites source.
public struct PageOutline: Sendable {
    public struct Heading: Identifiable, Sendable {
        public let id = UUID()
        public let title: String
        public let level: Int
        public let sourceRange: NSRange
    }
    public let source: PageOutlineSource
    public let headings: [Heading]
    public init(source: PageOutlineSource) {
        self.source = source
        var offset = 0
        headings = source.markdown.components(separatedBy: "\n").compactMap { line in
            defer { offset += line.utf16.count + 1 }
            let level = line.prefix { $0 == "#" }.count
            guard (1...6).contains(level), line.dropFirst(level).first == " " else { return nil }
            return Heading(title: String(line.dropFirst(level + 1)), level: level,
                sourceRange: NSRange(location: offset, length: line.utf16.count))
        }
    }
}
