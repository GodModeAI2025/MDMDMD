import Foundation
import Testing
@testable import SkriptumExport

let specimen = """
# Grüße 👨‍👩‍👧‍👦

Ein **starker** und *betonter* Text mit [Quelle](https://example.com?q=1&b=2).

3. Erster Punkt
4. Zweiter Punkt

> Zitat

```swift
let x = "<script>"
```

| Name | Wert |
| --- | --- |
| Ü | 42 |

Text mit Fußnote[^n].

[^n]: Wissenschaftliche *Anmerkung*.

1. [x] Ordered finished
2. [ ] Ordered open

- [x] Finished
- [ ] Open

<script>alert('bad')</script>
"""

@Test func htmlUsesSafeSemanticMarkdown() throws {
    let artifact = try ExportEngine.export(ExportInput(title: "Buch", markdown: specimen, author: "Autor", language: "de"), format: .html)
    let html = try #require(String(data: artifact.data, encoding: .utf8))
    #expect(html.contains("<h1"))
    #expect(html.contains("<strong>starker</strong>"))
    #expect(html.contains("<ol start=\"3\">"))
    #expect(html.contains("<table>"))
    #expect(html.contains("&lt;script&gt;"))
    #expect(!html.contains("<script>"))
    #expect(html.contains("Wissenschaftliche <em>Anmerkung</em>"))
    #expect(html.contains("👨‍👩‍👧‍👦"))
}

@Test func unsafeLinksAndMissingMediaFailExplicitly() {
    #expect(throws: ExportError.self) { try ExportEngine.export(ExportInput(title: "Document", markdown: "[Bad](javascript:alert%281%29)"), format: .html) }
    #expect(throws: ExportError.missingAsset("images/photo.png")) { try ExportEngine.export(ExportInput(title: "Document", markdown: "![Alt](images/photo.png)"), format: .epub) }
}

@Test func independentZIPAndXMLValidation() throws {
    #if os(macOS)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = ExportInput(title: "Grüße 🦊", markdown: specimen, author: "Autor", language: "de")
    for format in [ExportFormat.docx, .epub] {
        let artifact = try ExportEngine.export(input, format: format)
        try artifact.data.write(to: directory.appendingPathComponent("fixture.\(artifact.fileExtension)"))
    }
    let validation = """
import zipfile, pathlib, sys, xml.etree.ElementTree as E
p = pathlib.Path(sys.argv[1])
n = {'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
with zipfile.ZipFile(p/'fixture.docx') as z:
 assert z.testzip() is None
 for f in z.namelist():
  if f.endswith('.xml') or f.endswith('.rels'): E.fromstring(z.read(f))
 d=E.fromstring(z.read('word/document.xml'))
 assert len(d.findall('.//w:tbl', n)) == 1
 assert d.findall('.//w:numPr', n)
 assert any(x.get('{'+n['w']+'}val')=='Heading1' for x in d.findall('.//w:pStyle', n))
 text=''.join(d.itertext())
 expected = 'Gr\\u00fc\\u00dfe \\U0001f468\\u200d\\U0001f469\\u200d\\U0001f467\\u200d\\U0001f466'
 assert expected in text and 'starker' in text, repr(text)
 assert '\\u2611 Ordered finished' in text and '\\u2610 Ordered open' in text
 assert '\\u2611 Finished' in text and '\\u2610 Open' in text
 assert b'Wissenschaftliche' in z.read('word/footnotes.xml')
with zipfile.ZipFile(p/'fixture.epub') as z:
 assert z.testzip() is None
 assert z.infolist()[0].filename=='mimetype'
 assert z.infolist()[0].compress_type==zipfile.ZIP_STORED
 assert z.infolist()[0].extra==b''
 assert z.read('mimetype')==b'application/epub+zip'
 for f in z.namelist():
  if f.endswith(('.xml','.opf','.xhtml')): E.fromstring(z.read(f))
 opf=E.fromstring(z.read('EPUB/package.opf'))
 ns={'o':'http://www.idpf.org/2007/opf','d':'http://purl.org/dc/elements/1.1/'}
 assert opf.find('o:metadata/d:language', ns).text=='de'
 assert any(x.get('properties')=='nav' for x in opf.findall('o:manifest/o:item', ns))
 assert opf.find('o:spine/o:itemref', ns) is not None
 content=z.read('EPUB/content.xhtml').decode()
 assert '👨‍👩‍👧‍👦' in content
 assert '\\u2611 Ordered finished' in content and '\\u2610 Ordered open' in content
 assert '\\u2611 Finished' in content and '\\u2610 Open' in content
print('Independent ZIP/XML validation passed')
"""
    let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/python3"); task.arguments = ["-c", validation, directory.path]
    let pipe = Pipe(); task.standardOutput = pipe; task.standardError = pipe
    try task.run(); task.waitUntilExit()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(task.terminationStatus == 0, Comment(rawValue: output))
    #endif
}

@Test func footnotesRespectEscapingCodeAndMultipleParagraphs() throws {
    let markdown = "Literal \\[^n], actual[^n], `[^n]`.\n\n[^n]: First.\n\n    Second paragraph.\n\n```\n[^not-a-note]: unchanged\n```"
    let artifact = try ExportEngine.renderHTML(ExportInput(title: "Footnotes", markdown: markdown))
    let html = String(decoding: artifact.data, as: UTF8.self)
    #expect(html.contains("Literal [^n], actual<sup>"))
    #expect(html.contains("<code>[^n]</code>"))
    #expect(html.contains("<p>Second paragraph.</p>"))
    #expect(html.contains("[^not-a-note]: unchanged"))
}

@Test func tableAlignmentAndAssetsArePreserved() throws {
    let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII="))
    let input = ExportInput(title: "Assets", markdown: "| Left | Right |\n| :--- | ---: |\n| A | B |\n\n![Accessible image](images/a.png)", assets: ["images/a.png": ExportAsset(data: png, mediaType: "image/png")])
    let html = String(decoding: try ExportEngine.renderHTML(input).data, as: UTF8.self)
    #expect(html.contains("text-align:right"))
    #expect(html.contains("alt=\"Accessible image\""))
    #expect(html.contains("data:image/png;base64,"))
    #expect(try ExportEngine.export(input, format: .docx).data.count > png.count)
    #expect(try ExportEngine.export(input, format: .epub).data.count > png.count)
}

@Test func unsupportedInputNeverSilentlyDisappears() throws {
    #expect(throws: ExportError.self) { try ExportEngine.export(ExportInput(title: "Title", markdown: "bad\u{0}"), format: .epub) }
    #expect(throws: ExportError.missingFootnote("missing")) { try ExportEngine.renderHTML(ExportInput(title: "Title", markdown: "Text[^missing].")) }
    let relative = try ExportEngine.renderHTML(ExportInput(title: "Title", markdown: "[Other](other.md)"))
    #expect(relative.warnings.contains(where: { $0.contains("Relative document link") }))
}

@Test func unreferencedFootnoteChainsRetainEveryDefinition() throws {
    let input = ExportInput(title: "Notes", markdown: "Body.\n\n[^a]: Unused with nested[^b].\n\n[^b]: Nested definition.")
    let artifact = try ExportEngine.renderHTML(input)
    let html = String(decoding: artifact.data, as: UTF8.self)
    #expect(html.contains("Nested definition."))
    #expect(html.contains("id=\"note-2\""))
    #expect(artifact.warnings.contains(where: { $0.contains("Unreferenced footnote") }))
}

@Test func orderedAndUnorderedTaskListsPreserveCompletion() throws {
    let input = ExportInput(title: "Tasks", markdown: "- [x] Finished\n- [ ] Open\n\n1. [x] Ordered finished\n2. [ ] Ordered open")
    var parser = SemanticParser(input: input)
    let document = try parser.parse()
    func status(_ blocks: [SemanticBlock]) -> String {
        blocks.map { block in
            switch block {
            case .paragraph(let text): text.map(\.plain).joined()
            case .list(_, let items): items.map(status).joined(separator: "|")
            default: ""
            }
        }.joined(separator: "|")
    }
    let semantic = status(document.blocks)
    #expect(semantic.contains("☑ Finished"))
    #expect(semantic.contains("☐ Open"))
    #expect(semantic.contains("☑ Ordered finished"))
    #expect(semantic.contains("☐ Ordered open"))
    let html = String(decoding: try ExportEngine.renderHTML(input).data, as: UTF8.self)
    #expect(html.contains("☑ Ordered finished"))
    #expect(html.contains("☐ Ordered open"))
}

@Test func manuscriptPreservesChapterOrderAndIndependentFootnotes() throws {
    let chapters = [ExportInput(title: "Zweiter zuerst", markdown: "A[^n]\n\n[^n]: Erste Quelle"), ExportInput(title: "Erster danach", markdown: "```text\nunterminated"), ExportInput(title: "Letzter", markdown: "B[^n]\n\n[^n]: Zweite Quelle")]
    let result = try ExportEngine.exportManuscript(title: "Mein Buch", chapters: chapters, format: .html)
    let html = String(decoding: result.data, as: UTF8.self)
    #expect(try #require(html.range(of: "Zweiter zuerst")).lowerBound < #require(html.range(of: "Erster danach")).lowerBound)
    #expect(html.contains("<h1 id=\"heading-3\">Letzter</h1>"))
    #expect(html.contains("Erste Quelle"))
    #expect(html.contains("Zweite Quelle"))
    #expect(html.contains("href=\"#note-2\""))
    #expect(throws: ExportError.invalidMetadata("chapters")) { try ExportEngine.exportManuscript(title: "Empty", chapters: [], format: .html) }
}
