import Foundation
import CryptoKit

/// Keeps CPU work off the caller's actor and forwards cancellation to its worker.
/// A late result is never admitted after caller cancellation. Synchronous parsers
/// and system decoders still need to reach their next cancellation checkpoint.
public enum ExportWorker {
    public static func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = try await operation()
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
    }
}

/// Length-framed identity of every captured preview input, including declared
/// image types. Equal bytes with a different media type are different requests.
public enum ExportPreviewFingerprint {
    public static func signature(input: ExportInput, chapters: [ExportInput], profile: ExportProfile, pdf: Bool) -> String {
        var hash = SHA256()
        func append(_ value: Data) { hash.update(data: Data("\(value.count):".utf8)); hash.update(data: value) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        func document(_ value: ExportInput) {
            for text in [value.title, value.markdown, value.author, value.language] { append(Data(text.utf8)) }
            append((try? encoder.encode(value.theme)) ?? Data())
            append(Data(String(value.assets.count).utf8))
            for path in value.assets.keys.sorted() {
                guard let asset = value.assets[path] else { continue }
                append(Data(path.utf8)); append(Data(asset.mediaType.utf8)); append(asset.data)
            }
        }
        document(input)
        append(Data(profile.rawValue.utf8)); append(Data(String(pdf).utf8))
        append(Data(String(chapters.count).utf8))
        for chapter in chapters { document(chapter) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
