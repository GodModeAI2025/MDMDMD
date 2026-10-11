import Foundation

extension ExportEngine {
    /// Worker-local semantic PDF generation. This API does not select the app's
    /// export route. Structural tagging remains opt-in pending full acceptance.
    public static func renderSemanticPDF(_ input: ExportInput, profile: ExportProfile = .standard,
                                         taggedStructure: Bool = false) async throws -> ExportArtifact {
        try await ExportWorker.run {
            var parser = SemanticParser(input: input)
            let document = try parser.parse()
            let theme = input.theme ?? ExportTheme.preset(for: profile)
            let data = try PDFSemanticRenderer.render(document, theme: theme, taggedStructure: taggedStructure)
            try Task.checkCancellation()
            return ExportArtifact(data: data, fileExtension: "pdf", mediaType: "application/pdf",
                                  warnings: document.warnings)
        }
    }
    /// Chapters are parsed independently before heading/note/asset namespacing.
    public static func renderSemanticPDFManuscript(title: String, chapters: [ExportInput],
        author: String = "", language: String = "de", profile: ExportProfile = .manuscript,
        theme: ExportTheme? = nil, taggedStructure: Bool = false) async throws -> ExportArtifact {
        try await ExportWorker.run {
            let document = try semanticManuscript(title: title, chapters: chapters,
                                                  author: author, language: language, theme: theme)
            let data = try PDFSemanticRenderer.render(document, theme: theme ?? ExportTheme.preset(for: profile),
                                                      taggedStructure: taggedStructure)
            try Task.checkCancellation()
            return ExportArtifact(data: data, fileExtension: "pdf", mediaType: "application/pdf",
                                  warnings: document.warnings)
        }
    }

}
