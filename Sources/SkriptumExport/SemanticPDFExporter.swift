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
}
