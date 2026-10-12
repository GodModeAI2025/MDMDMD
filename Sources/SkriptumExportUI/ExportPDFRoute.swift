import Foundation
#if canImport(SkriptumExport)
import SkriptumExport
#endif

/// Shared production renderer for PDF preview and exported artifacts.
enum ExportPDFRoute {
    static func render(_ input: ExportInput, chapters: [ExportInput], profile: ExportProfile) async throws -> ExportArtifact {
        if chapters.isEmpty {
            return try await ExportEngine.renderSemanticPDF(input, profile: profile, taggedStructure: true)
        }
        return try await ExportEngine.renderSemanticPDFManuscript(
            title: input.title, chapters: chapters, author: input.author,
            language: input.language, profile: profile, theme: input.theme, taggedStructure: true)
    }
}
