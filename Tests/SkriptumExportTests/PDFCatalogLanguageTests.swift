import Foundation
import CoreGraphics
import Testing
@testable import SkriptumExport

@Test func semanticPDFCatalogDeclaresDocumentLanguage() throws {
    let writer = try PDFDocumentWriter(theme: .standard, title: "Language", taggedStructure: true, language: "de")
    try writer.paragraph(NSAttributedString(string: "Deutsch 🦊"))
    let data = try writer.finish()
    let provider = try #require(CGDataProvider(data: data as CFData))
    let pdf = try #require(CGPDFDocument(provider))
    var value: CGPDFStringRef?
    #expect(CGPDFDictionaryGetString(try #require(pdf.catalog), "Lang", &value))
    #expect(CGPDFStringCopyTextString(try #require(value)) as String? == "de")
}

@Test(arguments: ["de-DE", "en-GB", "zh-Hant-TW"])
func catalogLanguageUpdatePreservesOriginalPDFAndEmitsReaderVisibleMetadata(tag: String) throws {
    let writer = try PDFDocumentWriter(theme: .standard, title: "Languages >> (/Lang)", taggedStructure: true)
    try writer.paragraph(NSAttributedString(string: "Deutsch, English, 日本語. 🦊\n" + String(repeating: "Source-preserving metadata example.\n", count: 40)), language: tag)
    let original = try writer.finish()
    let result = try PDFCatalogLanguageFinalizer.add(tag, to: original)
    #expect(result.prefix(original.count) == original)
    let provider = try #require(CGDataProvider(data: result as CFData))
    let pdf = try #require(CGPDFDocument(provider))
    var value: CGPDFStringRef?
    #expect(CGPDFDictionaryGetString(try #require(pdf.catalog), "Lang", &value))
    #expect(CGPDFStringCopyTextString(try #require(value)) as String? == tag)
    #expect(try PDFCatalogLanguageFinalizer.add(tag, to: result) == result)
    if let path = ProcessInfo.processInfo.environment["SCRIPTUM_PDF_LANGUAGE_QA_OUTPUT"] {
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try original.write(to: directory.appending(path: tag + "-before.pdf"), options: .atomic)
        try result.write(to: directory.appending(path: tag + "-after.pdf"), options: .atomic)
    }
}
@Test(arguments: [false, true])
func semanticLanguageMetadataIsAvailableWithOrWithoutStructuralTags(tagged: Bool) throws {
    let writer = try PDFDocumentWriter(theme: .standard, title: "Regional language", taggedStructure: tagged, language: "EN_gb")
    try writer.paragraph(NSAttributedString(string: "Text 🦊"))
    let data = try writer.finish()
    let provider = try #require(CGDataProvider(data: data as CFData)), pdf = try #require(CGPDFDocument(provider))
    var value: CGPDFStringRef?
    #expect(CGPDFDictionaryGetString(try #require(pdf.catalog), "Lang", &value))
    #expect(CGPDFStringCopyTextString(try #require(value)) as String? == "en-GB")
    if tagged {
        var tree: CGPDFDictionaryRef?, logicalDocument: CGPDFDictionaryRef?, rootLanguage: CGPDFStringRef?
        #expect(CGPDFDictionaryGetDictionary(try #require(pdf.catalog), "StructTreeRoot", &tree))
        #expect(CGPDFDictionaryGetDictionary(try #require(tree), "K", &logicalDocument))
        #expect(CGPDFDictionaryGetString(try #require(logicalDocument), "Lang", &rootLanguage))
        #expect(CGPDFStringCopyTextString(try #require(rootLanguage)) as String? == "en-GB")
    }
}
@Test func malformedLanguageTagsFailBeforePDFCreationAndNilPreservesOriginal() throws {
    for value in ["", "de\n", "de-a", "de-a-test-a-more", "sl-rozaj-rozaj", "de--DE", "de-abcdefghij", "de) /Lang (en", "Deutsch🦊"] {
        #expect(throws: PDFCatalogLanguageFinalizer.Failure.invalidLanguage) { try PDFDocumentWriter(theme: .standard, title: "Invalid", language: value) }
    }
    for value in ["de", "zh-Hant-TW", "en-u-ca-gregory", "x-author", "i-klingon", "sgn-BE-FR", "sl-rozaj-biske"] {
        #expect(try PDFCatalogLanguageFinalizer.languageTag(value) != nil)
    }
    #expect(try PDFCatalogLanguageFinalizer.languageTag("en_IN") == "en-IN")
    let writer = try PDFDocumentWriter(theme: .standard, title: "No language")
    let data = try writer.finish()
    #expect(try PDFCatalogLanguageFinalizer.add(nil, to: data) == data)
    #expect(throws: PDFCatalogLanguageFinalizer.Failure.unsupportedPDF) { try PDFCatalogLanguageFinalizer.add("de", to: Data("not a PDF".utf8)) }
}

@Test func catalogLanguageAndElementOverrideStayDistinct() throws {
    let writer = try PDFDocumentWriter(theme: .standard, title: "Mixed language", taggedStructure: true, language: "en-GB")
    try writer.paragraph(NSAttributedString(string: "Une phrase française."), language: "fr-FR")
    let data = try writer.finish()
    let provider = try #require(CGDataProvider(data: data as CFData)), pdf = try #require(CGPDFDocument(provider))
    let catalog = try #require(pdf.catalog)
    var language: CGPDFStringRef?
    #expect(CGPDFDictionaryGetString(catalog, "Lang", &language))
    #expect(CGPDFStringCopyTextString(try #require(language)) as String? == "en-GB")
    var tree: CGPDFDictionaryRef?, document: CGPDFDictionaryRef?, paragraph: CGPDFDictionaryRef?
    #expect(CGPDFDictionaryGetDictionary(catalog, "StructTreeRoot", &tree))
    #expect(CGPDFDictionaryGetDictionary(try #require(tree), "K", &document))
    #expect(CGPDFDictionaryGetDictionary(try #require(document), "K", &paragraph))
    var override: CGPDFStringRef?
    #expect(CGPDFDictionaryGetString(try #require(paragraph), "Lang", &override))
    let actualOverride = CGPDFStringCopyTextString(try #require(override)) as String?
    #expect(actualOverride == "fr-FR")
}
