import Foundation
import Testing
@testable import SkriptumExport

@Test func eachChapterHeadingLinkTargetsItsOwnHeading() throws {
    let chapters = ["First", "Second"].map { title in
        ExportInput(title: title, markdown: "# Local\n\n[Jump](#heading-1)\n\n> ## Nested\n> [Nested jump](#heading-2)\n\nText[^n].\n\n[^n]: [Note jump](#heading-1)")
    }
    let result = try ExportEngine.exportManuscript(title: "Book", chapters: chapters, format: .html)
    let html = String(decoding: result.data, as: UTF8.self)
    #expect(html.contains("href=\"#heading-2\">Jump"))
    #expect(html.contains("href=\"#heading-5\">Jump"))
    #expect(html.contains("href=\"#heading-3\">Nested jump"))
    #expect(html.contains("href=\"#heading-6\">Nested jump"))
    #expect(html.contains("href=\"#heading-2\">Note jump"))
    #expect(html.contains("href=\"#heading-5\">Note jump"))
    #expect(chapters[1].markdown.contains("[Jump](#heading-1)"))
}

@Test func missingNumberedChapterHeadingCannotAccidentallyTargetAnotherChapter() {
    let chapters = [ExportInput(title: "First", markdown: "# Only\n\n[Bad](#heading-2)"), ExportInput(title: "Second", markdown: "# Other")]
    #expect(throws: ExportError.unsupportedMarkdown("Missing chapter heading target: #heading-2")) {
        try ExportEngine.exportManuscript(title: "Book", chapters: chapters, format: .html)
    }
}

@Test func remappedChapterTargetsExistInWordAndEPUBPackages() throws {
    #if os(macOS)
    let chapters = ["First", "Second"].map { ExportInput(title: $0, markdown: "# Local\n\n[Jump](#heading-1)") }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for format in [ExportFormat.docx, .epub] {
        let result = try ExportEngine.exportManuscript(title: "Book", chapters: chapters, format: format)
        try result.data.write(to: root.appendingPathComponent("book." + result.fileExtension))
    }
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    p.arguments = ["-c", """
import pathlib,zipfile,sys,xml.etree.ElementTree as E
root=pathlib.Path(sys.argv[1]); w='{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
with zipfile.ZipFile(root/'book.docx') as z:
 assert z.testzip() is None
 d=E.fromstring(z.read('word/document.xml'))
 jumps=[x.get(w+'anchor') for x in d.iter(w+'hyperlink') if ''.join(x.itertext())=='Jump']
 bookmarks={x.get(w+'name') for x in d.iter(w+'bookmarkStart')}
 assert jumps==['heading_2','heading_4'] and set(jumps)<=bookmarks
with zipfile.ZipFile(root/'book.epub') as z:
 assert z.testzip() is None
 d=E.fromstring(z.read('EPUB/content.xhtml')); h='{http://www.w3.org/1999/xhtml}'
 jumps=[x.get('href') for x in d.iter(h+'a') if ''.join(x.itertext())=='Jump']
 ids={x.get('id') for x in d.iter()}
 assert jumps==['#heading-2','#heading-4'] and all(x[1:] in ids for x in jumps)
""",root.path]
    try p.run(); p.waitUntilExit(); #expect(p.terminationStatus == 0)
    #endif
}
