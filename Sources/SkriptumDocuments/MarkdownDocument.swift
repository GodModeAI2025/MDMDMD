import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// External Markdown document. UTF-8 bytes are preserved without normalization.
@Observable
final class MarkdownDocument: Document {
    static let readableContentTypes: [UTType] = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
    var text: String
    init(text: String = "") { self.text = text }

    func reader(configuration: sending ReadConfiguration) -> sending FileWrapperDocumentReader<String> {
        FileWrapperDocumentReader(configuration) { wrapper in
            guard let data = wrapper.regularFileContents else { throw MarkdownDocumentError.notRegularFile }
            guard let content = String(data: data, encoding: .utf8) else { throw MarkdownDocumentError.invalidUTF8 }
            return content
        }
    }

    @MainActor
    func apply(snapshot: sending String, previous: sending String?) async throws { text = snapshot }

    func writer(configuration: sending WriteConfiguration) -> sending FileWrapperDocumentWriter<String> {
        FileWrapperDocumentWriter(configuration) { snapshot, _ in
            FileWrapper(regularFileWithContents: Data(snapshot.utf8))
        }
    }

    @MainActor
    func snapshot(contentType: UTType) async throws -> sending String { text }

    @MainActor
    func replaceText(_ replacement: String, undoManager: UndoManager?) {
        guard !replacement.utf8.elementsEqual(text.utf8) else { return }
        let original = text
        undoManager?.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated { document.replaceText(original, undoManager: undoManager) }
        }
        text = replacement
    }
}

