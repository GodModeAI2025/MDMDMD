import Foundation
#if canImport(SkriptumExport)
import SkriptumExport
#endif

/// Exercises the native renderer through the real UI without changing release defaults.
enum ExportPDFRoute {
    static var usesSemanticQA: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--scriptum-semantic-pdf-ui-qa")
        #else
        false
        #endif
    }

    static func render(_ input: ExportInput, chapters: [ExportInput], profile: ExportProfile) async throws -> ExportArtifact {
        if chapters.isEmpty {
            return try await ExportEngine.renderSemanticPDF(input, profile: profile)
        }
        return try await ExportEngine.renderSemanticPDFManuscript(
            title: input.title, chapters: chapters, author: input.author,
            language: input.language, profile: profile, theme: input.theme)
    }
}
