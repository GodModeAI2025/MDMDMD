import Foundation
import Testing
@testable import SkriptumExport

@Test(arguments: ["", " \t\n", "\u{00A0}\u{3000}", "Dr. Café e\u{301} & <Autor> 🦊", "  Autor 🦊  "])
func epubOptionalAuthorMetadata(_ author: String) throws {
    #if os(macOS)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data(author.utf8).write(to: directory.appendingPathComponent("author.txt"))
    let input = ExportInput(title: "Prüfbuch", markdown: "# Kapitel\n\nText.", author: author)
    let standalone = try ExportEngine.export(input, format: .epub)
    let manuscript = try ExportEngine.exportManuscript(title: "Prüfbuch", chapters: [input], author: author, format: .epub)
    try standalone.data.write(to: directory.appendingPathComponent("page.epub"))
    try manuscript.data.write(to: directory.appendingPathComponent("book.epub"))
    let validation = """
import pathlib, sys, zipfile, xml.etree.ElementTree as E
root, omitted = pathlib.Path(sys.argv[1]), sys.argv[2] == 'true'
expected = (root/'author.txt').read_bytes().decode('utf-8')
for path in (root/'page.epub', root/'book.epub'):
 with zipfile.ZipFile(path) as z:
  assert z.testzip() is None
  opf = E.fromstring(z.read('EPUB/package.opf'))
  creators = opf.findall('{http://www.idpf.org/2007/opf}metadata/{http://purl.org/dc/elements/1.1/}creator')
  if omitted:
   assert creators == [], 'Authorless publication must not contain an empty creator'
  else:
   assert len(creators) == 1 and creators[0].text == expected, 'Entered author must survive XML escaping exactly'
print('Optional creator metadata verified independently for page and manuscript')
"""
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = ["-c", validation, directory.path, String(author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)]
    let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
    try process.run(); process.waitUntilExit()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(process.terminationStatus == 0, Comment(rawValue: output))
    #endif
}
