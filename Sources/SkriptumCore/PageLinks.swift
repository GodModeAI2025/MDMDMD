import Foundation
import Markdown

/// A library-local identity. The URL carries no authority to open another library.
public struct PageLinkTarget: Equatable, Hashable, Sendable {
    public let pageID: UUID
    public let heading: String?
    public init(pageID: UUID, heading: String? = nil) { self.pageID = pageID; self.heading = heading }
    public init?(destination: String) {
        guard let c = URLComponents(string: destination), c.scheme?.lowercased() == "scriptum",
              c.host?.lowercased() == "page", c.user == nil, c.password == nil, c.port == nil,
              c.query == nil, c.path.count == 37, c.path.first == "/",
              let id = UUID(uuidString: String(c.path.dropFirst())), c.percentEncodedPath == c.path else { return nil }
        pageID = id; heading = c.fragment.flatMap { $0.isEmpty ? nil : $0 }
    }
    public var url: URL {
        var c = URLComponents(); c.scheme = "scriptum"; c.host = "page"
        c.path = "/" + pageID.uuidString; c.fragment = heading
        return c.url!
    }
}

/// CommonMark source coordinates (one-based lines and UTF-8 columns), not UTF-16 offsets.
public struct PageLinkSourceSpan: Equatable, Sendable {
    public let startLine: Int
    public let startColumn: Int
    public let endLine: Int
    public let endColumn: Int
    public init(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int) {
        self.startLine = startLine; self.startColumn = startColumn
        self.endLine = endLine; self.endColumn = endColumn
    }
}
public struct PageHeading: Equatable, Sendable {
    public let title: String
    public let level: Int
    public let slug: String
    /// Matches existing export HTML's heading-N anchors. Insertion changes ordinals.
    public let exportAnchor: String
    public let span: PageLinkSourceSpan?
}
public struct IndexedPageLink: Equatable, Sendable {
    public let sourcePageID: UUID
    public let sourceRevision: UUID
    public let target: PageLinkTarget
    public let destination: String
    public let label: String
    public let span: PageLinkSourceSpan?
}
public enum PageLinkResolution: Equatable, Sendable {
    case resolved(pageID: UUID, heading: PageHeading?)
    case missingPage, trashed, outsideSpace, missingHeading, ambiguousPage
}

/// An immutable index of one supplied library snapshot and explicit readable Spaces.
/// No parsing or resolving operation writes or normalizes a Page's source.
public struct PageLinkIndex: Sendable {
    public let libraryID: UUID
    public let spaceID: UUID
    public let readableSpaceIDs: Set<UUID>
    private let pages: [UUID: [Page]]
    private let headingIndex: [UUID: [PageHeading]]
    private let linkIndex: [UUID: [IndexedPageLink]]
    /// nil limits reads to the active Space. An explicit set is authoritative,
    /// including an empty set; callers supply their actual permission scope.
    public init(libraryID: UUID, spaceID: UUID, pages suppliedPages: [Page], readableSpaceIDs: Set<UUID>? = nil) {
        self.libraryID = libraryID; self.spaceID = spaceID
        self.readableSpaceIDs = readableSpaceIDs ?? [spaceID]
        pages = Dictionary(grouping: suppliedPages, by: \.id)
        var headings: [UUID: [PageHeading]] = [:], links: [UUID: [IndexedPageLink]] = [:]
        for page in suppliedPages where self.readableSpaceIDs.contains(page.spaceID) && page.trashedAt == nil && pages[page.id]?.count == 1 {
            var foundHeadings: [PageHeading] = [], foundLinks: [IndexedPageLink] = [], used = Set<String>()
            func visit(_ node: any Markup) {
                // Images may contain inline children; none are page-link occurrences.
                if node is Image || node is CodeBlock || node is InlineCode || node is HTMLBlock || node is InlineHTML { return }
                if let h = node as? Heading {
                    let title = Self.plain(h), base = Self.slug(title)
                    var candidate = base, suffix = 2
                    while used.contains(candidate) { candidate = "\(base)-\(suffix)"; suffix += 1 }
                    used.insert(candidate)
                    foundHeadings.append(.init(title: title, level: h.level, slug: candidate, exportAnchor: "heading-\(foundHeadings.count + 1)", span: Self.span(h)))
                }
                if let link = node as? Link, let destination = link.destination, let target = PageLinkTarget(destination: destination) {
                    foundLinks.append(.init(sourcePageID: page.id, sourceRevision: page.revision, target: target, destination: destination, label: Self.plain(link), span: Self.span(link)))
                }
                var htmlDepth: [String] = []
                for child in node.children {
                    if let html = child as? InlineHTML, let tag = Self.htmlTag(html.rawHTML) {
                        if tag.closing {
                            if let index = htmlDepth.lastIndex(of: tag.name) { htmlDepth.removeSubrange(index...) }
                        } else if !tag.isVoid { htmlDepth.append(tag.name) }
                        continue
                    }
                    if htmlDepth.isEmpty { visit(child) }
                }
            }
            visit(Document(parsing: page.markdown))
            headings[page.id] = foundHeadings; links[page.id] = foundLinks
        }
        headingIndex = headings; linkIndex = links
    }
    public func headings(on pageID: UUID) -> [PageHeading] { headingIndex[pageID] ?? [] }
    public func links(from pageID: UUID) -> [IndexedPageLink] { linkIndex[pageID] ?? [] }
    public func resolve(_ target: PageLinkTarget) -> PageLinkResolution {
        guard let matches = pages[target.pageID] else { return .missingPage }
        guard matches.count == 1, let page = matches.first else { return .ambiguousPage }
        guard readableSpaceIDs.contains(page.spaceID) else { return .outsideSpace }
        guard page.trashedAt == nil else { return .trashed }
        guard let fragment = target.heading else { return .resolved(pageID: page.id, heading: nil) }
        // Text slugs take precedence if they coincide with an export ordinal.
        guard let heading = headings(on: page.id).first(where: { $0.slug == fragment })
                ?? headings(on: page.id).first(where: { $0.exportAnchor == fragment }) else { return .missingHeading }
        return .resolved(pageID: page.id, heading: heading)
    }
    /// Includes only active readable-Space sources and successfully resolved targets.
    /// Repeated occurrences are retained so callers can navigate each source span.
    public func backlinks(to pageID: UUID) -> [IndexedPageLink] {
        linkIndex.values.flatMap { $0 }.filter {
            guard $0.target.pageID == pageID else { return false }
            if case .resolved = resolve($0.target) { return true }; return false
        }.sorted {
            if $0.sourcePageID != $1.sourcePageID { return $0.sourcePageID.uuidString < $1.sourcePageID.uuidString }
            if $0.span?.startLine != $1.span?.startLine { return ($0.span?.startLine ?? 0) < ($1.span?.startLine ?? 0) }
            return ($0.span?.startColumn ?? 0) < ($1.span?.startColumn ?? 0)
        }
    }
    private static func span(_ node: any Markup) -> PageLinkSourceSpan? {
        guard let r = node.range else { return nil }
        return .init(startLine: r.lowerBound.line, startColumn: r.lowerBound.column, endLine: r.upperBound.line, endColumn: r.upperBound.column)
    }
    private static func plain(_ node: any Markup) -> String {
        if let text = node as? Text { return text.string }
        if let code = node as? InlineCode { return code.code }
        if node is SoftBreak || node is LineBreak { return " " }
        if node is InlineHTML { return "" }
        return node.children.map { plain($0) }.joined()
    }
    // CommonMark keeps inline HTML as sibling tokens. Suppress Markdown links
    // enclosed by raw HTML tags too; raw HTML is not a trusted navigation surface.
    private static func htmlTag(_ raw: String) -> (name: String, closing: Bool, isVoid: Bool)? {
        guard raw.first == "<", raw.last == ">" else { return nil }
        var body = raw.dropFirst().dropLast()
        let closing = body.first == "/"
        if closing { body = body.dropFirst() }
        let name = String(body.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }).lowercased()
        guard !name.isEmpty else { return nil }
        let voids: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]
        return (name, closing, voids.contains(name) || body.last == "/")
    }
    private static func slug(_ title: String) -> String {
        let normalized = title.precomposedStringWithCanonicalMapping.lowercased()
        var output = "", pendingSeparator = false
        for scalar in normalized.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || CharacterSet.nonBaseCharacters.contains(scalar) {
                if pendingSeparator && !output.isEmpty { output += "-" }
                output.unicodeScalars.append(scalar); pendingSeparator = false
            } else { pendingSeparator = true }
        }
        return output.isEmpty ? "section" : output
    }
}
