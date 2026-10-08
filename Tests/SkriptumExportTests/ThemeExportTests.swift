import Foundation
import Testing
@testable import SkriptumExport

@Test func R13_themeValidationAndCodableRejectUnsafeValues() throws {
    var theme = ExportTheme.standard
    theme.bodySizePoints = .infinity
    #expect(throws: ExportError.self) { try theme.validate() }
    #expect(throws: ExportError.self) { try ExportEngine.renderHTML(ExportInput(title: "Unsafe", markdown: "Text", theme: theme)) }
    theme = .standard; theme.headingColorHex = "red; background:url(https://bad)"
    #expect(throws: ExportError.self) { try theme.validate() }
    theme = .standard; theme.marginsMM = 100
    #expect(throws: ExportError.self) { try theme.validate() }
    let valid = try ExportTheme(id: "custom", name: "My book", bodyFont: .palatino, bodySizePoints: 13, lineHeight: 1.8, paragraphSpacingPoints: 9, marginsMM: 20, paperSize: .letter, headingColorHex: "#AABBCC", includeTitle: true, includeTOC: true)
    #expect(try JSONDecoder().decode(ExportTheme.self, from: JSONEncoder().encode(valid)) == valid)
    let bad = Data("{\"id\":\"x\",\"name\":\"x\",\"bodyFont\":\"georgia\",\"bodySizePoints\":999,\"lineHeight\":1.5,\"paragraphSpacingPoints\":8,\"marginsMM\":20,\"paperSize\":\"a4\",\"headingColorHex\":\"#123456\",\"includeTitle\":true,\"includeTOC\":false}".utf8)
    #expect(throws: Error.self) { try JSONDecoder().decode(ExportTheme.self, from: bad) }
}

@Test func R13_themeAndTOCAffectHTMLWithoutChangingSource() throws {
    let source = "(toc)\n# One 👨‍👩‍👧‍👦\n\nParagraph.\n\n## Two\n\n```\n(toc)\n```"
    let theme = try ExportTheme(id: "custom", name: "Book", bodyFont: .palatino, bodySizePoints: 13, lineHeight: 1.8, paragraphSpacingPoints: 9, marginsMM: 20, paperSize: .letter, headingColorHex: "#AABBCC", includeTitle: true, includeTOC: false)
    let input = ExportInput(title: "Title", markdown: source, theme: theme)
    let html = String(decoding: try ExportEngine.renderHTML(input).data, as: UTF8.self)
    #expect(html.contains("font-size:13pt"))
    #expect(html.contains("line-height:1.8"))
    #expect(html.contains("size:Letter"))
    #expect(html.contains("margin:20mm"))
    #expect(html.contains("color:#AABBCC"))
    #expect(html.contains("href=\"#heading-1\""))
    #expect(html.contains("href=\"#heading-2\""))
    #expect(html.contains("<code>(toc)\n</code>"))
    #expect(input.markdown.utf8.elementsEqual(source.utf8))
    #expect(!html.contains("<p>(toc)</p>"))
}

@Test func R13_realZIPThemeGeometryBlogAssetsAndBookmarks() throws {
    #if os(macOS)
    let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII="))
    let theme = try ExportTheme(id: "book", name: "Book", bodyFont: .palatino, bodySizePoints: 13, lineHeight: 1.8, paragraphSpacingPoints: 9, marginsMM: 20, paperSize: .letter, headingColorHex: "#AABBCC", includeTitle: true, includeTOC: true)
    let input = ExportInput(title: "Book", markdown: "# Chapter\n\n![Alt](a.png)\n\nText[^n].\n\n[^n]: Note", author: "Author", assets: ["a.png": ExportAsset(data: png, mediaType: "image/png")], theme: theme)
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    for format in [ExportFormat.docx, .epub, .blog] { try ExportEngine.export(input, format: format).data.write(to: dir.appending(path: format.rawValue + ".zip")) }
    let script = """
import zipfile, pathlib, sys, json, xml.etree.ElementTree as E
p=pathlib.Path(sys.argv[1]); w={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}; attr='{'+w['w']+'}'
with zipfile.ZipFile(p/'docx.zip') as z:
 assert z.testzip() is None
 d=E.fromstring(z.read('word/document.xml')); styles=E.fromstring(z.read('word/styles.xml'))
 sz=d.find('.//w:pgSz',w); mar=d.find('.//w:pgMar',w)
 assert sz.get(attr+'w')=='12240' and sz.get(attr+'h')=='15840'
 assert mar.get(attr+'left')=='1134'
 assert any(e.get(attr+'val')=='26' for e in styles.findall('.//w:sz',w))
 assert any(e.get(attr+'ascii')=='Palatino' for e in styles.findall('.//w:rFonts',w))
 assert any(e.get(attr+'val')=='AABBCC' for e in styles.findall('.//w:color',w))
 assert any(e.get(attr+'line')=='432' and e.get(attr+'after')=='180' for e in styles.findall('.//w:spacing',w))
 names={e.get(attr+'name') for e in d.findall('.//w:bookmarkStart',w)}
 anchors={e.get(attr+'anchor') for e in d.findall('.//w:hyperlink',w)}
 assert 'heading_1' in names and 'heading_1' in anchors
 assert z.read('word/media/image1.png').startswith(b'\\x89PNG')
 assert b'Note' in z.read('word/footnotes.xml')
with zipfile.ZipFile(p/'epub.zip') as z:
 css=z.read('EPUB/style.css').decode(); content=z.read('EPUB/content.xhtml').decode()
 assert 'font-size:13pt' in css and 'margin:20mm' in css and 'size:Letter' in css
 assert 'href="#heading-1"' in content and 'note-1' in content
 assert z.read('EPUB/assets/image1.png').startswith(b'\\x89PNG')
 E.fromstring(content)
with zipfile.ZipFile(p/'blog.zip') as z:
 assert z.testzip() is None
 article=z.read('article.html').decode(); meta=json.loads(z.read('metadata.json'))
 assert article.startswith('<article') and '<html' not in article and '<script' not in article
 assert 'src="assets/image1.png"' in article and 'epub:type' not in article
 assert meta['title']=='Book' and meta['author']=='Author' and meta['theme']['id']=='book'
 assert z.read('assets/image1.png').startswith(b'\\x89PNG')
 assert 'Palatino' in z.read('styles.css').decode()
print('Theme ZIP/XML/blog integration passed')
"""
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3"); process.arguments = ["-c", script, dir.path]
    let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
    try process.run(); process.waitUntilExit()
    #expect(process.terminationStatus == 0, Comment(rawValue: String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)))
    #endif
}

@Test func R13_manuscriptThemeKeepsIndependentNotesAndMarkers() throws {
    let chapters = [ExportInput(title: "First", markdown: "(toc)\n\nA[^n]\n\n[^n]: Note A"), ExportInput(title: "Second", markdown: "```\n(toc)\n\n[^n]: code\n```\n\nB[^n]\n\n[^n]: Note B")]
    let html = String(decoding: try ExportEngine.exportManuscript(title: "Book", chapters: chapters, format: .html, theme: .standard).data, as: UTF8.self)
    #expect(html.contains("Note A") && html.contains("Note B"))
    #expect(html.contains("href=\"#heading-2\""))
    #expect(html.contains("[^n]: code"))
    #expect(html.contains("id=\"note-2\""))
}

@Test func R13_blogClipboardContentIsSemanticAndWarnsForPackagedMedia() throws {
    let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII="))
    let input = ExportInput(title: "Post", markdown: "# Heading\n\n**Bold** and [Link](https://example.com).\n\n![Alt](a.png)\n\nText[^n]\n\n[^n]: Footnote", assets: ["a.png": ExportAsset(data: png, mediaType: "image/png")])
    let content = try ExportEngine.blogContent(input)
    #expect(content.html.hasPrefix("<article"))
    #expect(content.html.contains("<strong>Bold</strong>"))
    #expect(!content.html.contains("<style") && !content.html.contains("<script"))
    #expect(content.plainText.contains("Bold and Link."))
    #expect(content.plainText.contains("Footnote"))
    #expect(!content.plainText.contains("**"))
    #expect(content.warnings.contains(where: { $0.contains("clipboard") }))
}

@Test func R13_longFencesDoNotActivateTOCOrFootnoteDefinitions() throws {
    let source = "````text\n```\n(toc)\n[^not-a-note]: literal\n````\n\n(toc)\n\n# Real heading"
    let html = String(decoding: try ExportEngine.renderHTML(ExportInput(title: "Fences", markdown: source)).data, as: UTF8.self)
    #expect(html.contains("[^not-a-note]: literal"))
    #expect(!html.contains("aria-label=\"Footnotes\""))
    #expect(html.components(separatedBy: "<nav aria-label=\"Contents\">").count == 2)
    #expect(html.contains("<pre><code class=\"language-text\">```\n(toc)\n[^not-a-note]: literal"))
}

@Test func R13_chapterBlogPackageSeparatesIdenticalAssetPaths() throws {
    #if os(macOS)
    let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII="))
    let chapters = ["First", "Second"].map { ExportInput(title: $0, markdown: "![\($0)](a.png)\n\nNote[^n].\n\n[^n]: \($0) source", assets: ["a.png": ExportAsset(data: png, mediaType: "image/png")]) }
    let result = try ExportEngine.exportManuscript(title: "Book", chapters: chapters, format: .blog, theme: .standard)
    let path = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".zip")
    try result.data.write(to: path); defer { try? FileManager.default.removeItem(at: path) }
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = ["-c", "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); h=z.read('article.html').decode(); assert 'assets/image1.png' in h and 'assets/image2.png' in h; assert 'First source' in h and 'Second source' in h and 'note-2' in h; assert z.read('assets/image1.png')==z.read('assets/image2.png'); assert z.testzip() is None", path.path]
    try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
    #endif
}

@Test(arguments: ["\t", " \t", "  \t", "\t "])
func R13_tabIndentedTOCAndFootnoteShapedLinesRemainCode(indent: String) throws {
    let source = indent + "(toc)\n" + indent + "[^code]: literal\n\n(toc)\n\n# Real heading"
    let input = ExportInput(title: "Tabs", markdown: source)
    let html = String(decoding: try ExportEngine.renderHTML(input).data, as: UTF8.self)
    let retainedSpace = indent == "\t " ? " " : ""
    #expect(html.contains("<pre><code>\(retainedSpace)(toc)\n\(retainedSpace)[^code]: literal"))
    #expect(!html.contains("aria-label=\"Footnotes\""))
    #expect(html.components(separatedBy: "<nav aria-label=\"Contents\">").count == 2)
    #expect(html.contains("href=\"#heading-1\""))
    #expect(input.markdown.utf8.elementsEqual(source.utf8))
}

@Test(arguments: ["\t", " \t", "  \t", "\t "])
func R13_tabIndentedBackticksNeverHideRealFootnoteDefinitions(indent: String) throws {
    let source = indent + "```\n" + indent + "(toc)\n" + indent + "[^code]: literal\n\nText[^actual].\n\n[^actual]: Actual note\n\n(toc)\n\n# Heading"
    let html = String(decoding: try ExportEngine.renderHTML(ExportInput(title: "Tabs", markdown: source)).data, as: UTF8.self)
    let retainedSpace = indent == "\t " ? " " : ""
    #expect(html.contains("<pre><code>\(retainedSpace)```\n\(retainedSpace)(toc)\n\(retainedSpace)[^code]: literal"))
    #expect(html.contains("Actual note"))
    #expect(html.contains("href=\"#note-1\""))
    #expect(html.components(separatedBy: "<nav aria-label=\"Contents\">").count == 2)
}
