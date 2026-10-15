import Foundation
import Testing
@testable import SkriptumCore

struct PageOutlineTests {
    @Test func ignoresHeadingExamplesInsideCodeAndRawHTML() {
        let source = """
        # Real

        ```markdown
        # Fenced example
        ```

            # Indented example

        > ~~~
        > # Quoted code example
        > ~~~

        <div>
        # HTML example
        </div>

        ## Final
        """
        let outline = PageOutline(source: .init(source))
        #expect(outline.headings.map(\.title) == ["Real", "Final"])
        #expect(outline.headings.map(\.level) == [1, 2])
        #expect(outline.source.markdown.utf8.elementsEqual(source.utf8))
    }

    @Test func setextNestedAndFormattedHeadingsHaveOriginalScrollTargets() throws {
        let source = "😀 Préface\r\n\r\nTitle *with emphasis*\r\n=====================\r\n\r\n> ## Quote `code`\r\n\r\n- ### Item [label](https://example.org)\r\n\r\n  ## Indented **bold** ##\r\n"
        let outline = PageOutline(source: .init(source))
        #expect(outline.headings.map(\.title) == ["Title with emphasis", "Quote code", "Item label", "Indented bold"])
        #expect(outline.headings.map(\.level) == [1, 2, 3, 2])
        let targets = ["Title *with emphasis*", "## Quote", "### Item", "## Indented"]
        for (heading, target) in zip(outline.headings, targets) {
            let expected = (source as NSString).range(of: target).location
            #expect(heading.sourceRange.location == expected)
            #expect(Range(heading.sourceRange, in: source) != nil)
        }
        let first = try #require(outline.headings.first)
        #expect((source as NSString).substring(with: first.sourceRange).contains("===") == true)
        #expect(outline.source.markdown.utf8.elementsEqual(source.utf8))
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func unicodeAndLineEndingsPreserveExactOffsets(ending: String) {
        let source = ["😀 e\u{301}", "", "## Café 😀", "", "Second", "------", "", "## Café 😀"].joined(separator: ending)
        let outline = PageOutline(source: .init(source))
        #expect(outline.headings.map(\.title) == ["Café 😀", "Second", "Café 😀"])
        #expect(outline.headings.map(\.sourceRange.location) == [
            (source as NSString).range(of: "## Café").location,
            (source as NSString).range(of: "Second").location,
            (source as NSString).range(of: "## Café", options: .backwards).location])
        #expect(Set(outline.headings.map(\.id)).count == outline.headings.count)
        for heading in outline.headings { #expect(Range(heading.sourceRange, in: source) != nil) }
    }

    @Test func changedUnicodeStorageInvalidatesCachedTargets() {
        let composed = PageOutlineSource("é\n\n# Target"), decomposed = PageOutlineSource("e\u{301}\n\n# Target")
        #expect(composed.markdown == decomposed.markdown)
        #expect(composed != decomposed)
        #expect(PageOutline(source: composed).headings.first?.sourceRange.location == 3)
        #expect(PageOutline(source: decomposed).headings.first?.sourceRange.location == 4)
    }
}
