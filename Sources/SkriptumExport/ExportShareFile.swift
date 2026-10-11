import Foundation
import Darwin

/// Publishes one complete file in operation-owned temporary storage. The caller
/// retains it for the receiving share process; cancellation never admits a URL.
public enum ExportShareFile {
    public static func write(_ data: Data, suggestedName: String, fileExtension: String) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scriptum-Export-" + UUID().uuidString, isDirectory: true)
        return try await write(data, suggestedName: suggestedName, fileExtension: fileExtension,
                               directory: directory)
    }

    static func write(_ data: Data, suggestedName: String, fileExtension: String, directory: URL,
                      checkpoint: @escaping @Sendable () throws -> Void = { try Task.checkCancellation() }) async throws -> URL {
        let lease = ExportShareFileLease()
        do {
            return try await ExportWorker.run {
                guard !fileExtension.isEmpty, fileExtension.utf8.count <= 16,
                      fileExtension.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) }) else {
                    throw ExportError.invalidMetadata("Export file extension")
                }
                let forbidden = CharacterSet(charactersIn: "/\\:\n\r").union(.controlCharacters)
                let name = String(suggestedName.components(separatedBy: forbidden).joined(separator: "-").prefix(100))
                let filename = (name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Scriptum" : name) + "." + fileExtension
                // Never claim or delete a directory that already belonged to anyone else.
                let created = directory.withUnsafeFileSystemRepresentation { path in
                    path.map { mkdir($0, 0o700) } ?? -1
                }
                guard created == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                await lease.claim(directory)
                try checkpoint()
                let staging = directory.appendingPathComponent(".partial")
                guard FileManager.default.createFile(atPath: staging.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let handle = try FileHandle(forWritingTo: staging)
                var closed = false
                defer { if !closed { try? handle.close() } }
                var index = data.startIndex
                while index < data.endIndex {
                    try Task.checkCancellation()
                    try checkpoint()
                    let end = index + min(256 * 1024, data.endIndex - index)
                    try handle.write(contentsOf: data[index..<end])
                    index = end
                }
                guard try handle.offset() == UInt64(data.count) else { throw CocoaError(.fileWriteUnknown) }
                try handle.synchronize()
                try handle.close(); closed = true
                try Task.checkCancellation()
                try checkpoint()
                let output = directory.appendingPathComponent(filename)
                try FileManager.default.moveItem(at: staging, to: output)
                try Task.checkCancellation()
                try checkpoint()
                return output
            }
        } catch {
            // ExportWorker awaits its worker even when canceled. Cleanup therefore
            // cannot race an unfinished writer or remove an unclaimed directory.
            await lease.discard()
            throw error
        }
    }
}

private actor ExportShareFileLease {
    private var directory: URL?
    func claim(_ directory: URL) { self.directory = directory }
    func discard() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }
}
