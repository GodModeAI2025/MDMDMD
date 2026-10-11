import Foundation
import Testing
@testable import SkriptumExport

@Test func previewFingerprintInvalidatesWhenIdenticalImageBytesChangeDeclaredType() throws {
    let asset = try orientedPhoto(6)
    let input = ExportInput(title: "Preview", markdown: "![Figure](photo.jpg)", assets: ["photo.jpg": asset])
    let artifact = try ExportEngine.export(input, format: .html)
    #expect(!artifact.data.isEmpty)
    var invalid = input
    invalid.assets["photo.jpg"]?.mediaType = "image/png"
    #expect(input.assets["photo.jpg"]?.data == invalid.assets["photo.jpg"]?.data)
    do { _ = try ExportEngine.export(invalid, format: .html); Issue.record("Mismatched image type accepted") }
    catch ExportError.unsupportedAsset {} catch { Issue.record("Unexpected error: \(error)") }
    #expect(ExportPreviewFingerprint.signature(input: input, chapters: [], profile: .standard, pdf: false)
        != ExportPreviewFingerprint.signature(input: invalid, chapters: [], profile: .standard, pdf: false))
    let base = ExportInput(title: "Manuscript", markdown: "")
    #expect(ExportPreviewFingerprint.signature(input: base, chapters: [input], profile: .standard, pdf: true)
        != ExportPreviewFingerprint.signature(input: base, chapters: [invalid], profile: .standard, pdf: true))
}

@Test func previewFingerprintIsStableAcrossAssetOrderButRetainsChapterOrderAndBoundaries() throws {
    let photo = try orientedPhoto(6)
    var a = ExportInput(title: "ab", markdown: "c", assets: ["a.jpg": photo, "b.jpg": photo])
    var b = a; b.assets = ["b.jpg": photo, "a.jpg": photo]
    func signature(_ input: ExportInput, _ chapters: [ExportInput] = []) -> String {
        ExportPreviewFingerprint.signature(input: input, chapters: chapters, profile: .standard, pdf: false)
    }
    #expect(signature(a) == signature(b))
    b.title = "a"; b.markdown = "bc"
    #expect(signature(a) != signature(b))
    #expect(signature(a, [a, b]) != signature(a, [b, a]))
    let old = signature(a)
    a.language = "fr-FR"; a.author = "Another author"
    #expect(signature(a) != old)
}
