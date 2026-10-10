import Foundation
import Testing
@testable import SkriptumExport

@Test func tocInsideListFenceStaysLiteralWhileExternalMarkerWorks() throws {
    let source = "# Chapter\n\n- ```text\n  (toc)\n  After marker\n  ```\n\n(toc)\n"
    let artifact = try ExportEngine.export(ExportInput(title: "Book", markdown: source), format: .html)
    let html = String(decoding: artifact.data, as: UTF8.self)
    #expect(html.contains("<code class=\"language-text\">(toc)\nAfter marker\n</code>"))
    #expect(html.components(separatedBy: "<nav aria-label=\"Contents\">").count == 2)
}

@Test func tocCRLFProseMarkerGetsItsOwnParagraphWithoutChangingSource() throws {
    let source = "# Chapter\r\n\r\nBefore\r\n(toc)\r\nAfter\r\n"
    let input = ExportInput(title: "Book", markdown: source)
    let artifact = try ExportEngine.export(input, format: .html)
    let html = String(decoding: artifact.data, as: UTF8.self)
    #expect(html.contains("<p>Before</p>"))
    #expect(html.contains("<p>After</p>"))
    #expect(html.contains("<nav aria-label=\"Contents\">"))
    #expect(input.markdown.utf8.elementsEqual(source.utf8))
}

@Test func tocInUnfinishedListFenceNeverCreatesNavigation() throws {
    let source = "# Chapter\n\n- ~~~text\n  (toc)\n  Still code\n"
    let artifact = try ExportEngine.export(ExportInput(title: "Book", markdown: source), format: .html)
    let html = String(decoding: artifact.data, as: UTF8.self)
    #expect(html.contains("(toc)\nStill code"))
    #expect(!html.contains("<nav"))
}
