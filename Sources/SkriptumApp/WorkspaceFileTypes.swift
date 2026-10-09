import Foundation

struct SharedMarkdown: Identifiable {
    let id = UUID()
    let url: URL
}

enum MarkdownDocumentError: Error, LocalizedError {
    case notRegularFile, invalidUTF8
    var errorDescription: String? {
        switch self {
        case .notRegularFile: "Das Dokument ist keine lesbare Textdatei."
        case .invalidUTF8: "Die Datei ist kein gültiges UTF-8-Dokument. Das Original wurde nicht verändert."
        }
    }
}
