import Foundation
import Testing
@testable import SkriptumCore

struct PageLinksTests {
    @Test func identityScopeAndBacklinks() {
        let space = UUID(), other = UUID(), library = UUID()
        var target = Page(spaceID: space, title: "Old", markdown: "# Héllo 世界\r\n# Héllo 世界\r\n")
        let destination = PageLinkTarget(pageID: target.id, heading: "héllo-世界-2")
        let source = Page(spaceID: space, title: "Source", markdown: "😀 [label](\(destination.url.absoluteString))\r\n")
        let original = source.markdown
        target.title = "Renamed"
        let index = PageLinkIndex(libraryID: library, spaceID: space, pages: [source, target])
        #expect(index.links(from: source.id).count == 1)
        #expect(index.backlinks(to: target.id).map(\.sourcePageID) == [source.id])
        #expect(index.resolve(destination) == .resolved(pageID: target.id, heading: index.headings(on: target.id)[1]))
        #expect(source.markdown.utf8.elementsEqual(original.utf8))
        #expect(PageLinkIndex(libraryID: library, spaceID: other, pages: [target]).resolve(destination) == .outsideSpace)
        target.trashedAt = Date()
        #expect(PageLinkIndex(libraryID: library, spaceID: space, pages: [source,target]).resolve(destination) == .trashed)
    }
    @Test func syntaxIsParsedNotSubstringMatched() {
        let space = UUID(), target = Page(spaceID: UUID(), title: "T")
        let url = PageLinkTarget(pageID: target.id).url.absoluteString
        let markdown = "`[inline](\(url))`\n\n```\n[fenced](\(url))\n```\n\n    [indented](\(url))\n\n<img src=\"\(url)\">\n\n![image](\(url))\n\n<a href=\"ignored\">[html child](\(url))</a>\n\n[real][ref]\n\n[ref]: \(url)\n"
        let source = Page(spaceID: space, title: "S", markdown: markdown)
        let index = PageLinkIndex(libraryID: UUID(), spaceID: space, pages: [source])
        #expect(index.links(from: source.id).map(\.label) == ["real"])
        #expect(index.resolve(PageLinkTarget(pageID: target.id)) == .missingPage)
        #expect(index.backlinks(to: target.id).isEmpty)
    }
    @Test func strictDestinationsAndSlugCollisions() {
        let id = UUID()
        #expect(PageLinkTarget(destination: "scriptum://page/\(id)?secret=x") == nil)
        #expect(PageLinkTarget(destination: "scriptum://evil/\(id)") == nil)
        #expect(PageLinkTarget(destination: "scriptum://page/\(id)/extra") == nil)
        #expect(PageLinkTarget(destination: "https://page/\(id)") == nil)
        let space = UUID(), page = Page(spaceID: space, title: "T", markdown: "# A\n# A\n# A-2\n# !!!\n")
        let index = PageLinkIndex(libraryID: UUID(), spaceID: space, pages: [page])
        #expect(index.headings(on: page.id).map(\.slug) == ["a", "a-2", "a-2-2", "section"])
        #expect(index.resolve(PageLinkTarget(pageID: id)) == .missingPage)
        #expect(index.resolve(PageLinkTarget(pageID: page.id, heading: "absent")) == .missingHeading)
        #expect(index.resolve(PageLinkTarget(pageID: page.id, heading: "heading-2")) == .resolved(pageID: page.id, heading: index.headings(on: page.id)[1]))
    }
    @Test func sourceCoordinatesAndStaleSnapshot() {
        let space = UUID(), target = Page(spaceID: UUID(), title: "T")
        var page = Page(spaceID: space, title: "S", markdown: "😀 e\u{301} [visit](\(PageLinkTarget(pageID: target.id).url))\r\n")
        let initial = PageLinkIndex(libraryID: UUID(), spaceID: space, pages: [page])
        let occurrence = initial.links(from: page.id)[0]
        #expect(occurrence.span?.startLine == 1)
        #expect(occurrence.span?.startColumn == 10)
        #expect(occurrence.sourceRevision == page.revision)
        page.blocks = [Block(markdown: "changed")]; page.revision = UUID()
        #expect(initial.links(from: page.id)[0] == occurrence)
        #expect(initial.links(from: page.id)[0].sourceRevision != page.revision)
    }
    @Test func excludedSourcesAndAmbiguousIdentity() {
        let space = UUID(), other = UUID()
        let target = Page(spaceID: space, title: "T", markdown: "# Heading")
        let destination = PageLinkTarget(pageID: target.id, heading: "missing").url
        var source = Page(spaceID: space, title: "S", markdown: "[broken](\(destination))")
        let index = PageLinkIndex(libraryID: UUID(), spaceID: space, pages: [source,target])
        #expect(index.links(from: source.id).count == 1)
        #expect(index.backlinks(to: target.id).isEmpty)
        source.trashedAt = Date()
        #expect(PageLinkIndex(libraryID: UUID(), spaceID: space, pages: [source,target]).links(from: source.id).isEmpty)
        source.trashedAt = nil; source.spaceID = other
        #expect(PageLinkIndex(libraryID: UUID(), spaceID: space, pages: [source,target]).links(from: source.id).isEmpty)
        #expect(PageLinkIndex(libraryID: UUID(), spaceID: space, pages: [target,target]).resolve(PageLinkTarget(pageID: target.id)) == .ambiguousPage)
    }

    @Test func explicitReadableSpacesDoNotExpandDefaultScope() {
        let active = UUID(), readable = UUID(), forbidden = UUID(), library = UUID()
        var target = Page(spaceID: readable, title: "Before", markdown: "# Shared heading")
        let hidden = Page(spaceID: forbidden, title: "Hidden", markdown: "# Secret")
        let destination = PageLinkTarget(pageID: target.id, heading: "shared-heading")
        let source = Page(spaceID: active, title: "Source", markdown: "[read](\(destination.url))")
        let readableSource = Page(spaceID: readable, title: "Other source", markdown: "[local](\(PageLinkTarget(pageID: source.id).url))")
        let forbiddenSource = Page(spaceID: forbidden, title: "Hidden source", markdown: "[no](\(destination.url))")
        let pages = [source,target,hidden,readableSource,forbiddenSource]
        let defaults = PageLinkIndex(libraryID: library, spaceID: active, pages: pages)
        #expect(defaults.resolve(destination) == .outsideSpace)
        #expect(defaults.headings(on: target.id).isEmpty)
        #expect(defaults.links(from: readableSource.id).isEmpty)
        target.title = "After"
        let scoped = PageLinkIndex(libraryID: library, spaceID: active, pages: [source,target,hidden,readableSource,forbiddenSource], readableSpaceIDs: [active,readable])
        #expect(scoped.resolve(destination) == .resolved(pageID: target.id, heading: scoped.headings(on: target.id)[0]))
        #expect(scoped.backlinks(to: target.id).map(\.sourcePageID) == [source.id])
        #expect(scoped.backlinks(to: source.id).map(\.sourcePageID) == [readableSource.id])
        #expect(scoped.resolve(PageLinkTarget(pageID: hidden.id)) == .outsideSpace)
        #expect(scoped.links(from: forbiddenSource.id).isEmpty)
        let empty = PageLinkIndex(libraryID: library, spaceID: active, pages: pages, readableSpaceIDs: [])
        #expect(empty.links(from: source.id).isEmpty)
        #expect(empty.resolve(PageLinkTarget(pageID: source.id)) == .outsideSpace)
    }

}
