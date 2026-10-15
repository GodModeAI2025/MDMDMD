import Foundation
import PDFKit
import Testing
import SkriptumExport

@Test func imageOnlyHeadingRetainsItsInternalLinkAndContentsDestination() async throws {
    var theme = ExportTheme.standard
    theme.includeTitle = false
    theme.includeTOC = true
    let source = """
    [JumpToImageHeading](#heading-1)

    # [![ImageHeadingWitness](photo.jpg)](https://example.com/figure)

    BodyAfterImageHeading 🦊.

    # TextHeadingWitness

    BodyAfterTextHeading.
    """
    let artifact = try await ExportEngine.renderSemanticPDF(
        ExportInput(title: "Image heading destinations", markdown: source,
                    assets: ["photo.jpg": try orientedPhoto(1)], theme: theme), taggedStructure: true)
    if let path = ProcessInfo.processInfo.environment["SCRIPTUM_IMAGE_HEADING_QA_OUTPUT"] {
        try artifact.data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    let pdf = try #require(PDFDocument(data: artifact.data))
    let annotations = (0..<pdf.pageCount).flatMap { pdf.page(at: $0)?.annotations ?? [] }
    let links = annotations.filter { $0.type == "Link" && $0.url == nil }
    let image = try #require(annotations.first { $0.url?.absoluteString == "https://example.com/figure" })
    // Two generated contents entries plus the author's explicit internal link.
    #expect(links.count == 3)
    for link in links {
        #expect(link.destination?.page != nil, "Every exported internal link must resolve, including an image-only heading.")
    }
    #expect(links.filter { $0.destination?.page === image.page && abs(($0.destination?.point.y ?? 0) - image.bounds.maxY) < 0.01 }.count == 2)
    let text = try #require(pdf.string)
    #expect(text.contains("BodyAfterImageHeading"))
    #expect(text.filter { $0 == "🦊" }.count == 1)
    #expect(text.contains("BodyAfterTextHeading."))
}

@Test func imageLeadingHeadingDestinationDoesNotMoveToLaterTextOrImage() async throws {
    let source = """
    [JumpToImageHeading](#heading-1)

    # [![FirstImage](photo.jpg)](https://example.com/first) HeadingSuffix [![SecondImage](photo.jpg)](https://example.com/second)

    BodyWitness.
    """
    let artifact = try await ExportEngine.renderSemanticPDF(
        ExportInput(title: "Mixed heading destination", markdown: source,
                    assets: ["photo.jpg": try orientedPhoto(1)]), taggedStructure: true)
    let pdf = try #require(PDFDocument(data: artifact.data))
    let annotations = (0..<pdf.pageCount).flatMap { pdf.page(at: $0)?.annotations ?? [] }
    let jump = try #require(annotations.first { $0.type == "Link" && $0.url == nil })
    let firstImage = try #require(annotations.first { $0.url?.absoluteString == "https://example.com/first" })
    let destination = try #require(jump.destination)
    #expect(destination.page === firstImage.page)
    #expect(abs(destination.point.y - firstImage.bounds.maxY) < 0.01)
    #expect(pdf.string?.contains("HeadingSuffix") == true)
    #expect(pdf.string?.contains("BodyWitness.") == true)
}
