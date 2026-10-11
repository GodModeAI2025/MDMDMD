import Foundation
import PDFKit
import Testing
@testable import SkriptumExport

@Test func semanticPDFTraversesMarkdownContainersNotesAndOriginalImage() throws {
    let source = """
    # Kapitel 🦊

    Ein **wichtiger** [Link](https://example.com) mit Note[^n].

    > Zitat mit *Betonung*.

    3. Erster Eintrag
    4. Zweiter Eintrag

    ```swift
    let value = "🦊"
    ```

    [![Foto](photo.jpg)](#heading-1)

    Nach dem Bild.

    [^n]: Fußnote mit 🦊.
    """
    let asset = try orientedPhoto(6)
    var parser = SemanticParser(input: ExportInput(title: "Buch", markdown: source + "\n" + String(repeating: "Weiterer Absatz 🦊.\n\n", count: 100), assets: ["photo.jpg": asset]))
    let semantic = try parser.parse()
    let pdf = try #require(PDFDocument(data: PDFSemanticRenderer.render(semantic, theme: .standard)))
    let text = try #require(pdf.string)
    for expected in ["Kapitel 🦊", "wichtiger", "Zitat mit", "3. Erster Eintrag", "4. Zweiter Eintrag", "let value", "Nach dem Bild.", "Fußnote mit 🦊"] {
        #expect(text.contains(expected))
    }
    let annotations = (0..<pdf.pageCount).flatMap { pdf.page(at: $0)?.annotations ?? [] }
    #expect(annotations.contains { $0.url?.absoluteString == "https://example.com" })
    #expect(annotations.contains { $0.destination?.page?.string?.contains("Kapitel 🦊") == true })
    #expect(annotations.contains { $0.destination?.page?.string?.contains("Fußnote mit 🦊") == true })
    #expect(pdf.pageCount > 1)
    #expect(semantic.input.assets["photo.jpg"]?.data == asset.data)
}

@Test func semanticPDFTableRetainsEveryRowAndRepeatsHeader() throws {
    let rows = (0..<90).map { "| Row \($0) 🦊 | [Link \($0)](https://example.com/\($0)) |" }.joined(separator: "\n")
    var parser = SemanticParser(input: ExportInput(title: "Table", markdown: "| Name | Target |\n|:---|---:|\n" + rows + "\n\nAfter table."))
    let document = try parser.parse()
    let data = try PDFSemanticRenderer.render(document, theme: .standard)
    if let path = ProcessInfo.processInfo.environment["SCRIPTUM_PDF_TABLE_QA_OUTPUT"] {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    let pdf = try #require(PDFDocument(data: data))
    #expect(pdf.pageCount > 1)
    let text = try #require(pdf.string)
    #expect(text.filter { $0 == "🦊" }.count == 90)
    for index in 0..<90 { #expect(text.contains("Row \(index) 🦊")) }
    let links = (0..<pdf.pageCount).flatMap { pdf.page(at: $0)?.annotations ?? [] }
    #expect(links.count == 90)
    let geometry = try PDFPageCursor(theme: .standard)
    #expect(links.allSatisfy { abs($0.bounds.maxX - geometry.content.maxX + 6) < 0.1 })
    for index in 0..<pdf.pageCount {
        let page = try #require(pdf.page(at: index))
        if page.string?.contains("Row ") == true { #expect(page.string?.contains("Name") == true) }
    }
    #expect(text.contains("After table."))
}

@Test func semanticPDFContentsResolveNestedHeadingsAfterPageBreaks() throws {
    for explicit in [false, true] {
        let marker = explicit ? "(toc)\n\n" : ""
        let source = marker + "# Erstes Kapitel\n\n" + String(repeating: "Text 🦊.\n\n", count: 120)
            + "---\n\n> ## Zweites Kapitel\n>\n> Zieltext.\n"
        var parser = SemanticParser(input: ExportInput(title: "Contents", markdown: source))
        let document = try parser.parse()
        var theme = ExportTheme.standard; theme.includeTOC = true
        let pdf = try #require(PDFDocument(data: PDFSemanticRenderer.render(document, theme: theme)))
        #expect(pdf.pageCount > 1)
        let allText = try #require(pdf.string)
        #expect(allText.components(separatedBy: "Erstes Kapitel").count - 1 == 2)
        #expect(allText.components(separatedBy: "Zweites Kapitel").count - 1 == 2)
        let links = (0..<pdf.pageCount).flatMap { pdf.page(at: $0)?.annotations ?? [] }
        #expect(links.count == 2)
        #expect(links.contains { $0.destination?.page?.string?.contains("Zieltext.") == true })
        #expect(links.allSatisfy { $0.destination?.page != nil })
        #expect(allText.filter { $0 == "🦊" }.count == 120)
    }
}

@Test func semanticHeadingUsesKeepWithNextForAdjacentParagraph() throws {
    let geometry = try PDFPageCursor(theme: .standard)
    let adapter = try PDFInlineAdapter(theme: .standard, footnoteIDs: [])
    guard case .text(let one)? = try adapter.fragments([.text("Filler\n")]).first else { Issue.record("Missing text"); return }
    let height = try PDFParagraphLayout(text: one, width: geometry.content.width, lineHeight: 1.65).lineHeights[0]
    let count = Int((geometry.content.height - 65) / height)
    let input = ExportInput(title: "Keep", markdown: "")
    let document = SemanticDocument(input: input, blocks: [
        .paragraph([.text(String(repeating: "Filler\n", count: count))]),
        .heading(1, [.text("Together")]),
        .paragraph([.text(String(repeating: "Following 🦊\n", count: 10))])
    ], footnotes: [], warnings: [], imagePaths: [])
    let pdf = try #require(PDFDocument(data: PDFSemanticRenderer.render(document, theme: .standard)))
    #expect(pdf.page(at: 0)?.string?.contains("Together") == false)
    #expect(pdf.page(at: 1)?.string?.contains("Together") == true)
    #expect(pdf.page(at: 1)?.string?.contains("Following 🦊") == true)
}

@Test func semanticHeadingChainStaysWithParagraphOrCode() throws {
    let theme = ExportTheme.standard
    let geometry = try PDFPageCursor(theme: theme)
    let adapter = try PDFInlineAdapter(theme: theme, footnoteIDs: [])
    guard case .text(let filler)? = try adapter.fragments([.text("Filler\n")]).first else { return }
    let height = try PDFParagraphLayout(text: filler, width: geometry.content.width,
        lineHeight: CGFloat(theme.lineHeight)).lineHeights[0]
    let count = Int((geometry.content.height - 115) / height)
    for code in [false, true] {
        let content = String(repeating: "Following 🦊\n", count: 10)
        let document = SemanticDocument(input: ExportInput(title: "Chain", markdown: ""), blocks: [
            .paragraph([.text(String(repeating: "Filler\n", count: count))]),
            .heading(1, [.text("First heading")]),
            .heading(2, [.text("Second heading")]),
            .heading(3, [.text("Third heading")]),
            code ? .code(content, "swift") : .paragraph([.text(content)])
        ], footnotes: [], warnings: [], imagePaths: [])
        let data = try PDFSemanticRenderer.render(document, theme: theme)
        if let path = ProcessInfo.processInfo.environment["SCRIPTUM_PDF_HEADING_CHAIN_QA_OUTPUT"] {
            try data.write(to: URL(fileURLWithPath: path + (code ? "-code.pdf" : "-text.pdf")), options: .atomic)
        }
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.page(at: 0)?.string?.contains("First heading") == false)
        #expect(pdf.page(at: 1)?.string?.contains("First heading") == true)
        #expect(pdf.page(at: 1)?.string?.contains("Second heading") == true)
        #expect(pdf.page(at: 1)?.string?.contains("Third heading") == true)
        #expect(pdf.page(at: 1)?.string?.contains("Following 🦊") == true)
        #expect(pdf.string?.filter { $0 == "🦊" }.count == 10)
    }
}

@Test func codeFirstEndnoteNumberAndBodyShareDestinationPage() throws {
    let theme = ExportTheme.standard
    let geometry = try PDFPageCursor(theme: theme)
    let adapter = try PDFInlineAdapter(theme: theme, footnoteIDs: ["n"])
    guard case .text(let filler)? = try adapter.fragments([.text("Filler\n")]).first else { return }
    let height = try PDFParagraphLayout(text: filler, width: geometry.content.width,
        lineHeight: CGFloat(theme.lineHeight)).lineHeights[0]
    let count = Int((geometry.content.height - 65) / height)
    let document = SemanticDocument(input: ExportInput(title: "Note", markdown: ""), blocks: [
        .paragraph([.text(String(repeating: "Filler\n", count: count - 1)), .footnote("n")])
    ], footnotes: [("n", [.code(String(repeating: "NoteCode 🦊 [^literal]\n", count: 10), "swift")])], warnings: [], imagePaths: [])
    let data = try PDFSemanticRenderer.render(document, theme: theme)
    if let path = ProcessInfo.processInfo.environment["SCRIPTUM_PDF_CODE_NOTE_QA_OUTPUT"] {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    let pdf = try #require(PDFDocument(data: data))
    let annotations = (0..<pdf.pageCount).flatMap { pdf.page(at: $0)?.annotations ?? [] }
    let target = try #require(annotations.first?.destination?.page)
    #expect(target.string?.contains("1.") == true)
    #expect(target.string?.contains("NoteCode") == true)
    #expect(pdf.page(at: 0)?.string?.contains("1.") == false)
    #expect(pdf.string?.filter { $0 == "🦊" }.count == 10)
    #expect(pdf.string?.components(separatedBy: "[^literal]").count == 11)
}

@Test func oversizedHeadingChainSplitsWithoutDroppingItsBody() throws {
    for code in [false, true] {
        let headings = (1...30).map { SemanticBlock.heading(($0 % 3) + 1, [.text("ChainHeading-\($0)-End")]) }
        let body = String(repeating: "BodyAfterChain 🦊\n", count: 10)
        let document = SemanticDocument(input: ExportInput(title: "Long chain", markdown: ""),
            blocks: headings + [code ? .code(body, "swift") : .paragraph([.text(body)])],
            footnotes: [], warnings: [], imagePaths: [])
        let data = try PDFSemanticRenderer.render(document, theme: .standard)
        if let path = ProcessInfo.processInfo.environment["SCRIPTUM_PDF_LONG_HEADING_QA_OUTPUT"] {
            try data.write(to: URL(fileURLWithPath: path + (code ? "-code.pdf" : "-text.pdf")), options: .atomic)
        }
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount > 1)
        let text = try #require(pdf.string)
        var prior = text.startIndex
        for index in 1...30 {
            let token = "ChainHeading-\(index)-End"
            let range = try #require(text.range(of: token, range: prior..<text.endIndex))
            #expect(text.components(separatedBy: token).count == 2)
            prior = range.upperBound
        }
        let lastHeading = try #require((0..<pdf.pageCount).first { pdf.page(at: $0)?.string?.contains("ChainHeading-30-End") == true })
        let firstBody = try #require((0..<pdf.pageCount).first { pdf.page(at: $0)?.string?.contains("BodyAfterChain") == true })
        #expect(lastHeading == firstBody)
        #expect(text.filter { $0 == "🦊" }.count == 10)
    }
}
