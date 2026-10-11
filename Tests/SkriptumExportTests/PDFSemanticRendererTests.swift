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

@Test func semanticPDFRejectsUnsupportedTablesInsteadOfDroppingContent() throws {
    var parser = SemanticParser(input: ExportInput(title: "Table", markdown: "| A | B |\n|---|---|\n| 1 | 2 |"))
    let document = try parser.parse()
    #expect(throws: ExportError.unsupportedMarkdown("PDF table layout")) {
        try PDFSemanticRenderer.render(document, theme: .standard)
    }
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
