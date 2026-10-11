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
