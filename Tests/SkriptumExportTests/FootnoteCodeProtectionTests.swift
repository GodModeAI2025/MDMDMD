import Foundation
import Testing
@testable import SkriptumExport

@Test func footnoteDefinitionsInsideListFencesRemainCode() throws {
    let source = "- ```text\n  [^n]: Codebeispiel\n  ```\n\nText[^n].\n\n[^n]: Echte Anmerkung\n"
    let result = try ExportEngine.export(ExportInput(title: "Book", markdown: source), format: .html)
    let html = String(decoding: result.data, as: UTF8.self)
    #expect(html.contains("[^n]: Codebeispiel"))
    #expect(html.contains("Echte Anmerkung"))
    #expect(!result.warnings.contains(where: { $0.contains("Unreferenced") }))
}

@Test func unfinishedContainerFenceKeepsFootnoteSyntaxLiteral() throws {
    let source = "- ~~~text\n  [^n]: Codebeispiel\n  Text[^n]\n"
    let result = try ExportEngine.export(ExportInput(title: "Book", markdown: source), format: .html)
    let html = String(decoding: result.data, as: UTF8.self)
    #expect(html.contains("[^n]: Codebeispiel"))
    #expect(html.contains("Text[^n]"))
    #expect(!html.contains("<aside"))
}

@Test func actualWordAndEPUBSeparateCodeExampleFromRealFootnote() throws {
    #if os(macOS)
    let source = "- ```text\n  [^n]: Codebeispiel\n  ```\n\nText[^n].\n\n[^n]: Echte Anmerkung\n"
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for format in [ExportFormat.docx,.epub] {
        let result = try ExportEngine.export(ExportInput(title: "Book", markdown: source), format: format)
        try result.data.write(to: root.appendingPathComponent("book." + result.fileExtension))
    }
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    p.arguments = ["-c", """
import pathlib,zipfile,sys,xml.etree.ElementTree as E
root=pathlib.Path(sys.argv[1])
with zipfile.ZipFile(root/'book.docx') as z:
 assert z.testzip() is None
 d=E.fromstring(z.read('word/document.xml')); n=E.fromstring(z.read('word/footnotes.xml'))
 assert '[^n]: Codebeispiel' in ''.join(d.itertext())
 assert 'Echte Anmerkung' in ''.join(n.itertext()) and 'Codebeispiel' not in ''.join(n.itertext())
with zipfile.ZipFile(root/'book.epub') as z:
 assert z.testzip() is None
 d=E.fromstring(z.read('EPUB/content.xhtml')); h='{http://www.w3.org/1999/xhtml}'
 codes=[''.join(e.itertext()) for e in d.iter(h+'code')]
 notes=[''.join(e.itertext()) for e in d.iter(h+'aside')]
 assert any('[^n]: Codebeispiel' in c for c in codes)
 assert len(notes)==1 and 'Echte Anmerkung' in notes[0] and 'Codebeispiel' not in notes[0]
""",root.path]
    try p.run(); p.waitUntilExit(); #expect(p.terminationStatus == 0)
    #endif
}
