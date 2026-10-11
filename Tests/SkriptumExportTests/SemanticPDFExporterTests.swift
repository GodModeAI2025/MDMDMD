import Foundation
import PDFKit
import Testing
import SkriptumExport

@Test func publicSemanticPDFEntryReturnsThemeMetadataAndUnicodeArtifact() async throws {
    let theme = try ExportTheme(id: "letter", name: "Letter", paperSize: .letter)
    let input = ExportInput(title: "Public export", markdown: "# Heading\n\nBody 🦊\n\n3. Listed text\n", author: "Author", theme: theme)
    let original = input.markdown
    let artifact = try await ExportEngine.renderSemanticPDF(input, profile: .manuscript)
    #expect(artifact.fileExtension == "pdf")
    #expect(artifact.mediaType == "application/pdf")
    #expect(artifact.data.starts(with: Data("%PDF-".utf8)))
    let pdf = try #require(PDFDocument(data: artifact.data))
    #expect(pdf.string?.contains("Body 🦊") == true)
    #expect(pdf.string?.contains("Listed text") == true)
    #expect(pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == input.title)
    #expect(pdf.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String == input.author)
    let page = try #require(pdf.page(at: 0))
    #expect(abs(page.bounds(for: .mediaBox).width - 612) < 0.01)
    #expect(abs(page.bounds(for: .mediaBox).height - 792) < 0.01)
    #expect(input.markdown == original)
}

@Test func publicSemanticPDFEntryRetainsParserWarningsAndCancellation() async throws {
    let artifact = try await ExportEngine.renderSemanticPDF(ExportInput(title: "Literal", markdown: "<div>Visible HTML</div>"))
    #expect(artifact.warnings.contains("Raw HTML exported as visible text."))
    let canceled = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await ExportEngine.renderSemanticPDF(ExportInput(title: "", markdown: "Invalid metadata"))
    }
    await #expect(throws: CancellationError.self) { try await canceled.value }
}

@Test func publicSemanticPDFEntryPropagatesMissingAttachmentWithoutFallback() async throws {
    await #expect(throws: ExportError.missingAsset("missing.png")) {
        try await ExportEngine.renderSemanticPDF(ExportInput(title: "Missing image", markdown: "![Image](missing.png)"))
    }
}

@Test func publicPDFManuscriptKeepsChapterLocalNotesAssetsAndHeadingTargets() async throws {
    let first = ExportInput(title: "Chapter One", markdown:
        "## Only One\n\n[Jump One](#heading-1)\n\nRef First[^n]\n\n"
        + String(repeating: "Long body 🦊\n\n", count: 100)
        + "\n![First](photo.jpg)\n\n[^n]: First note.\n",
        assets: ["photo.jpg": try orientedPhoto(1)])
    let second = ExportInput(title: "Chapter Two", markdown:
        "## Only Two\n\n[Jump Two](#heading-1)\n\nRef Second[^n]\n\n![Second](photo.jpg)\n\n[^n]: Second note.\n",
        assets: ["photo.jpg": try orientedPhoto(6)])
    let artifact = try await ExportEngine.renderSemanticPDFManuscript(title: "Book", chapters: [first, second])
    if let path = ProcessInfo.processInfo.environment["SCRIPTUM_PDF_MANUSCRIPT_QA_OUTPUT"] {
        try artifact.data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    let pdf = try #require(PDFDocument(data: artifact.data))
    let text = try #require(pdf.string)
    for expected in ["Chapter One", "Chapter Two", "Only One", "Only Two", "First note.", "Second note."] {
        #expect(text.contains(expected))
    }
    #expect(text.filter { $0 == "🦊" }.count == 100)
    let links = (0..<pdf.pageCount).flatMap { pdf.page(at: $0)?.annotations ?? [] }
    #expect(links.contains { $0.destination?.page?.string?.contains("Only One") == true })
    #expect(links.contains { $0.destination?.page?.string?.contains("Only Two") == true })
    #expect(links.contains { $0.destination?.page?.string?.contains("First note.") == true })
    #expect(links.contains { $0.destination?.page?.string?.contains("Second note.") == true })
    #expect(pdf.pageCount > 1)
}

@Test func publicPDFManuscriptRejectsEmptyAndMissingChapterHeadingTarget() async throws {
    await #expect(throws: ExportError.invalidMetadata("chapters")) {
        try await ExportEngine.renderSemanticPDFManuscript(title: "Book", chapters: [])
    }
    await #expect(throws: ExportError.unsupportedMarkdown("Missing chapter heading target: #heading-9")) {
        try await ExportEngine.renderSemanticPDFManuscript(title: "Book", chapters: [
            ExportInput(title: "Chapter", markdown: "# Heading\n\n[Missing](#heading-9)")])
    }
}

@Test func publicPDFManuscriptUnfinishedFenceDoesNotConsumeNextChapter() async throws {
    let artifact = try await ExportEngine.renderSemanticPDFManuscript(title: "Book", chapters: [
        ExportInput(title: "First", markdown: "```swift\nlet token = 1"),
        ExportInput(title: "Second", markdown: "# Real heading\n\nIndependent body 🦊")
    ])
    let pdf = try #require(PDFDocument(data: artifact.data))
    let text = try #require(pdf.string)
    #expect(text.contains("let token = 1"))
    #expect(text.contains("Real heading"))
    #expect(text.contains("Independent body 🦊"))
}
