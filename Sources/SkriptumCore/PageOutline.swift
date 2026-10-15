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
        let indexed = PageLinkIndex.headings(in: source.markdown)
        let ranged = indexed.compactMap { heading -> (PageHeading, PageLinkSourceSpan)? in
            guard let span = heading.span else { return nil }
            return (heading, span)
        }
        let ranges = PageLinkSourceSpan.utf16Ranges(ranged.map { $0.1 }, in: source.markdown)
        headings = zip(ranged, ranges).compactMap { pair, range in
            guard let range else { return nil }
            return Heading(title: pair.0.title, level: pair.0.level, sourceRange: range)
        }
    }
}
