import Foundation
import PDFKit
import AppKit
import Testing
@testable import SkriptumExport

/// Check publication artifacts, rather than only the shared theme calculation.
@Test(arguments: [8.0, 13.5, 36.0])
func headingThemeMatchesDOCXHTMLAndEPUB(bodySize: Double) throws {
    #if os(macOS)
    let expected: [Double] = switch bodySize {
    case 8: [16, 14.5, 13, 11, 9.5, 8]
    case 13.5: [27, 24.5, 21.5, 19, 16, 13.5]
    default: [72, 65, 57.5, 50.5, 43, 36]
    }
    let theme = try ExportTheme(bodySizePoints: bodySize, includeTitle: true)
    let markdown = (1...6).map { String(repeating: "#", count: $0) + " Level\($0)\n\nBody." }.joined(separator: "\n\n")
    let input = ExportInput(title: "Book", markdown: markdown, theme: theme)
    let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for format in [ExportFormat.docx, .html, .epub] {
        try ExportEngine.export(input, format: format).data.write(to: directory.appendingPathComponent("page." + format.rawValue))
    }
    if bodySize == 13.5, let evidence = headingThemeEvidenceDirectory() {
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        for format in ["docx", "html", "epub"] {
            try Data(contentsOf: directory.appendingPathComponent("page." + format))
                .write(to: evidence.appendingPathComponent("page." + format))
        }
        try Data(markdown.utf8).write(to: evidence.appendingPathComponent("source.md"))
        try JSONEncoder().encode(theme).write(to: evidence.appendingPathComponent("theme.json"))
    }
    try JSONEncoder().encode(expected).write(to: directory.appendingPathComponent("sizes.json"))
    let validation = """
import pathlib, sys, json, re, zipfile, xml.etree.ElementTree as E
root=pathlib.Path(sys.argv[1]); expected=json.loads((root/'sizes.json').read_text())
w={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}; a='{'+w['w']+'}'
with zipfile.ZipFile(root/'page.docx') as z:
 styles=E.fromstring(z.read('word/styles.xml'))
 for style_id, size in [(f'Heading{i+1}',size) for i,size in enumerate(expected)]+[('Title', expected[0])]:
  style=styles.find(f"w:style[@w:styleId='{style_id}']",w)
  actual=float(style.find('w:rPr/w:sz',w).get(a+'val'))/2
  assert actual==size, f'{style_id}: expected {size} pt, DOCX has {actual} pt'
with zipfile.ZipFile(root/'page.epub') as z: epub_css=z.read('EPUB/style.css').decode()
for name, css in [('HTML preview', (root/'page.html').read_text()), ('EPUB', epub_css)]:
 for level, size in enumerate(expected,1):
  match=re.search(r'h'+str(level)+r'\\{font-size:([0-9.]+)pt\\}',css)
  assert match is not None, f'{name}: h{level} inherits browser heading size'
  assert float(match.group(1))==size, f'{name}: h{level} size differs from DOCX'
print('DOCX styles, HTML preview and EPUB heading sizes match for all levels and title')
"""
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = ["-c", validation, directory.path]
    let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
    try process.run(); process.waitUntilExit()
    #expect(process.terminationStatus == 0, Comment(rawValue: String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)))
    #endif
}

@Test(arguments: [8.0, 13.5, 36.0])
func headingThemeMatchesRenderedPDF(bodySize: Double) async throws {
    let expected: [Double] = switch bodySize {
    case 8: [16, 14.5, 13, 11, 9.5, 8]
    case 13.5: [27, 24.5, 21.5, 19, 16, 13.5]
    default: [72, 65, 57.5, 50.5, 43, 36]
    }
    let theme = try ExportTheme(bodySizePoints: bodySize, includeTitle: true)
    let markdown = (1...6).map { String(repeating: "#", count: $0) + " Level\($0)\n\nBody." }.joined(separator: "\n\n")
    let artifact = try await ExportEngine.renderSemanticPDF(ExportInput(title: "Book", markdown: markdown, theme: theme))
    if bodySize == 13.5, let evidence = headingThemeEvidenceDirectory() {
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        try artifact.data.write(to: evidence.appendingPathComponent("page.pdf"))
    }
    let pdf = try #require(PDFDocument(data: artifact.data))
    for (text, size) in [("Book", expected[0])] + expected.enumerated().map({ ("Level\($0.offset + 1)", $0.element) }) {
        let selection = try #require(pdf.findString(text, withOptions: []).first)
        let attributed = try #require(selection.attributedString)
        let font = try #require(attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(abs(font.pointSize - size) < 0.02, "\(text): expected \(size) pt, PDF has \(font.pointSize) pt")
    }
}

private func headingThemeEvidenceDirectory() -> URL? {
    ProcessInfo.processInfo.environment["SCRIPTUM_HEADING_THEME_EVIDENCE"].map { URL(fileURLWithPath: $0, isDirectory: true) }
}
