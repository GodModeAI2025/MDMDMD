import Foundation
import PDFKit
import CryptoKit
import Testing
import SkriptumExport

@Test(.enabled(if: ProcessInfo.processInfo.environment["SCRIPTUM_LONG_MIXED_QA_OUTPUT"] != nil))
func publicLongMixedManuscriptPreservesChaptersMediaTablesNotesAndUnicode() async throws {
    let output = try #require(ProcessInfo.processInfo.environment["SCRIPTUM_LONG_MIXED_QA_OUTPUT"])
    let root = URL(fileURLWithPath: output)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let phrase = "Professional writing brings sources, arguments, evidence and precise language together. Every chapter preserves its original content while readers move through paragraphs, illustrations, tables and explanatory notes."
    var chapters: [ExportInput] = []
    for chapter in 1...4 {
        var source = "## LocalStart-C\(chapter)\n\n[LocalJump-C\(chapter)](#heading-1) and note[^n].\n\n"
        for paragraph in 0..<400 {
            if paragraph % 100 == 0 {
                let section = paragraph / 100
                source += "### MediaHead-C\(chapter)-S\(section)\n\n[![Image-C\(chapter)-S\(section)](photo.jpg)](https://example.com/C\(chapter)/S\(section))\n\n"
                source += "| Table-C\(chapter)-S\(section) | Evidence |\n|---|---|\n"
                for row in 0..<8 {
                    let media = row < 2 ? "![Cell-C\(chapter)-S\(section)-R\(row)](photo.jpg) " : ""
                    source += "| Row-C\(chapter)-S\(section)-R\(row) 🦊 | \(media)Verified evidence |\n"
                }
                source += "\n> Quote-C\(chapter)-S\(section) 🦊\n\n1. ListOne-C\(chapter)-S\(section) 🦊\n2. ListTwo-C\(chapter)-S\(section) 🦊\n\n```swift\nCode-C\(chapter)-S\(section) 🦊 (toc) [^literal]\n```\n\n"
            }
            source += "P-C\(chapter)-\(paragraph)-END \(phrase) \(phrase) 🦊 日本語 Ελληνικά русский café é.\n\n"
        }
        source += "[^n]: Note-C\(chapter)-END 🦊\n"
        chapters.append(ExportInput(title: "Chapter-C\(chapter)", markdown: source,
            assets: ["photo.jpg": try orientedPhoto([1,6,3,8][chapter-1])]))
    }
    let snapshots = chapters.map { Data($0.markdown.utf8) }
    let sourceFoxes = chapters.reduce(0) { $0 + $1.markdown.filter { $0 == "🦊" }.count }
    let themes = [
        try ExportTheme(id: "a4-georgia", name: "A4 Georgia", includeTitle: true, includeTOC: true),
        try ExportTheme(id: "a4-courier", name: "A4 Courier", bodyFont: .courierNew, lineHeight: 2, includeTitle: true, includeTOC: true),
        try ExportTheme(id: "letter-helvetica", name: "Letter Helvetica", bodyFont: .helvetica, paperSize: .letter, includeTitle: true, includeTOC: true)
    ]
    var receipts: [[String: Any]] = []
    for theme in themes {
        let started = Date()
        let artifact = try await ExportEngine.renderSemanticPDFManuscript(title: "Long Mixed Manuscript", chapters: chapters,
            author: "Scriptum QA", language: "de-DE", theme: theme, taggedStructure: true)
        try artifact.data.write(to: root.appending(path: theme.id + ".pdf"), options: .atomic)
        #expect(artifact.warnings.isEmpty)
        let pdf = try #require(PDFDocument(data: artifact.data))
        let text = try #require(pdf.string)
        let normalized = text.components(separatedBy: .whitespacesAndNewlines).joined()
        #expect(pdf.pageCount > 100 && pdf.pageCount < 3000)
        #expect(text.filter { $0 == "🦊" }.count == sourceFoxes)
        #expect(normalized.components(separatedBy: "(toc)").count == 17)
        #expect(normalized.components(separatedBy: "[^literal]").count == 17)
        let annotations = (0..<pdf.pageCount).flatMap { pdf.page(at: $0)?.annotations ?? [] }
        #expect(annotations.filter { $0.url?.host == "example.com" }.count == 16)
        let expression = try NSRegularExpression(pattern: "P-C[1-4]-[0-9]+-END")
        let range = NSRange(normalized.startIndex..., in: normalized)
        let nativeText = normalized as NSString
        let markers = expression.matches(in: normalized, range: range).map { nativeText.substring(with: $0.range) }
        let expectedMarkers = (1...4).flatMap { chapter in (0..<400).map { "P-C\(chapter)-\($0)-END" } }
        #expect(markers == expectedMarkers)
        for chapter in 1...4 {
            #expect(normalized.components(separatedBy: "Note-C\(chapter)-END").count == 2)
            #expect(annotations.contains { $0.destination?.page?.string?.contains("LocalStart-C\(chapter)") == true })
            #expect(annotations.contains { $0.destination?.page?.string?.contains("Note-C\(chapter)-END") == true })
            #expect(Data(chapters[chapter-1].markdown.utf8) == snapshots[chapter-1])
        }
        #expect(normalized.components(separatedBy: "日本語").count == 1601)
        #expect(normalized.components(separatedBy: "Ελληνικά").count == 1601)
        #expect(normalized.components(separatedBy: "русский").count == 1601)
        let page = try #require(pdf.page(at: 0))
        #expect(abs(page.bounds(for: .mediaBox).width - CGFloat(theme.paperSize.widthMM * 72 / 25.4)) < 0.01)
        receipts.append(["theme":theme.id, "pages":pdf.pageCount, "bytes":artifact.data.count,
            "pdfSHA256":SHA256.hash(data:artifact.data).map { String(format:"%02x",$0) }.joined(),
            "sourceBytes":snapshots.reduce(0) { $0+$1.count }, "sourceWords":chapters.reduce(0) { $0+$1.markdown.split(whereSeparator: { $0.isWhitespace }).count },
            "paragraphMarkers":1600, "foxesExpected":sourceFoxes, "foxesActual":text.filter { $0 == "🦊" }.count,
            "externalImageLinks":annotations.filter { $0.url?.host == "example.com" }.count,
            "seconds":Date().timeIntervalSince(started), "warnings":artifact.warnings])
        try JSONSerialization.data(withJSONObject: receipts, options: [.prettyPrinted,.sortedKeys]).write(to: root.appending(path: "PUBLIC_EXPORT_RECEIPTS.json"), options: .atomic)
    }
    let inputReceipt: [String: Any] = ["chapters":snapshots.enumerated().map { ["chapter":$0.offset+1,"bytes":$0.element.count,"sha256":SHA256.hash(data:$0.element).map { String(format:"%02x",$0) }.joined()] },"paragraphs":1600,"tables":16,"tableRows":128,"figures":48,"notes":4,"literalCodeBlocks":16,"foxes":sourceFoxes]
    try JSONSerialization.data(withJSONObject: inputReceipt, options: [.prettyPrinted,.sortedKeys]).write(to:root.appending(path:"INPUT_RECEIPT.json"),options:.atomic)
}
