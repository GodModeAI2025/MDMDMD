import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum RecoveryEvidenceError: Error { case unsafeEntry, bounds, destinationExists, changed, missingLibrary }
public struct RecoveryEvidenceReceipt: Codable, Sendable {
    public struct File: Codable, Sendable { public let path: String; public let bytes: Int64; public let sha256: String }
    public let formatVersion: Int
    public let capturedAt: Date
    public let files: [File]
    public let directories: [String]
    public let excludedPaths: [String]
}

/// Copies opaque original bytes into a portable, stored ZIP; it never decodes,
/// repairs or removes source content. Publication follows complete verification.
public enum RecoveryEvidenceExporter {
    public static func archive(from source: URL, to destination: URL) async throws -> RecoveryEvidenceReceipt {
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) { try capture(source: source, destination: destination) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    private struct Item {
        let path: String
        let url: URL
        let directory: Bool
        let version: LibraryDiskAccess.Version?
    }
    private static func inventory(_ root: URL) throws -> [Item] {
        var result: [Item] = []
        var pending: [(URL, String)] = [(root, "")]
        while let (directory, prefix) = pending.popLast() {
            try Task.checkCancellation()
            guard try FileManager.default.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else { throw RecoveryEvidenceError.unsafeEntry }
            // Every directory read throws on failure; enumeration cannot silently skip an unreadable subtree.
            for listed in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                try Task.checkCancellation()
                let name = listed.lastPathComponent
                let url = directory.appendingPathComponent(name)
                let path = prefix.isEmpty ? name : prefix + "/" + name
                if path == ".library.lock" { continue }
                guard !path.isEmpty, path.utf8.count <= 1024, !path.contains("\\"),
                      !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { throw RecoveryEvidenceError.unsafeEntry }
                let type = try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
                guard type == .typeDirectory || type == .typeRegular else { throw RecoveryEvidenceError.unsafeEntry }
                let version = type == .typeRegular ? try LibraryDiskAccess.version(of: url) : nil
                guard type == .typeDirectory || version != nil else { throw RecoveryEvidenceError.changed }
                if let version { guard version.size >= 0, version.size <= 512 * 1024 * 1024 else { throw RecoveryEvidenceError.bounds } }
                result.append(Item(path: path, url: url, directory: type == .typeDirectory, version: version))
                guard result.count < 10_000 else { throw RecoveryEvidenceError.bounds }
                if type == .typeDirectory { pending.append((url, path)) }
            }
        }
        return result.sorted { Array($0.path.utf8).lexicographicallyPrecedes(Array($1.path.utf8)) }
    }
    private static func capture(source: URL, destination: URL) throws -> RecoveryEvidenceReceipt {
        let root = source.resolvingSymlinksInPath().standardizedFileURL
        let target = destination.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(destination.lastPathComponent)
        guard target != root, !target.path.hasPrefix(root.path + "/"),
              try FileManager.default.attributesOfItem(atPath: source.path)[.type] as? FileAttributeType == .typeDirectory else { throw RecoveryEvidenceError.unsafeEntry }
        guard (try? FileManager.default.attributesOfItem(atPath: target.path)) == nil else { throw RecoveryEvidenceError.destinationExists }
        let staged = target.deletingLastPathComponent().appendingPathComponent(".scriptum-rescue-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staged) }
        return try LibraryDiskAccess.withExclusiveLock(directory: root) {
            let items = try inventory(root)
            guard items.contains(where: { $0.path == "library.json" && !$0.directory }) else { throw RecoveryEvidenceError.missingLibrary }
            var total: Int64 = 0
            for item in items { total += item.version?.size ?? 0; guard total <= 2 * 1024 * 1024 * 1024 else { throw RecoveryEvidenceError.bounds } }
            let writer = try Writer(url: staged)
            defer { writer.close() }
            var files: [RecoveryEvidenceReceipt.File] = [], directories: [String] = []
            for item in items {
                if item.directory {
                    try writer.data(Data(), name: "Originals/" + item.path + "/")
                    directories.append(item.path)
                } else {
                    let digest = try writer.file(item.url, name: "Originals/" + item.path, expectedBytes: item.version!.size)
                    guard try LibraryDiskAccess.version(of: item.url) == item.version else { throw RecoveryEvidenceError.changed }
                    files.append(.init(path: item.path, bytes: item.version!.size, sha256: digest))
                }
            }
            let final = try inventory(root)
            guard items.count == final.count, zip(items, final).allSatisfy({ $0.path == $1.path && $0.directory == $1.directory && $0.version == $1.version }) else { throw RecoveryEvidenceError.changed }
            let receipt = RecoveryEvidenceReceipt(formatVersion: 1, capturedAt: Date(), files: files, directories: directories, excludedPaths: [".library.lock"])
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try writer.data(encoder.encode(receipt), name: "manifest.json")
            try writer.finish()
            try writer.verifyReadback(staged)
            let verified = try inventory(root)
            guard items.count == verified.count, zip(items, verified).allSatisfy({ $0.path == $1.path && $0.directory == $1.directory && $0.version == $1.version }) else { throw RecoveryEvidenceError.changed }
            try Task.checkCancellation()
            // Same-directory hard-link publication is atomic and cannot replace
            // a target created after the initial existence check.
            guard link(staged.path, target.path) == 0 else {
                if errno == EEXIST { throw RecoveryEvidenceError.destinationExists }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return receipt
        }
    }
    private final class Writer {
        private let handle: FileHandle
        private var position: UInt64 = 0, central = Data()
        private var entries: UInt16 = 0
        private var outputHash = SHA256()
        private var closed = false
        init(url: URL) throws {
            let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        }
        func close() { if !closed { try? handle.close(); closed = true } }
        private func write(_ bytes: Data) throws {
            try Task.checkCancellation()
            guard position + UInt64(bytes.count) <= UInt64(UInt32.max) else { throw RecoveryEvidenceError.bounds }
            try handle.write(contentsOf: bytes); outputHash.update(data: bytes); position += UInt64(bytes.count)
        }
        private func begin(_ name: String) throws -> UInt32 {
            guard entries < UInt16.max else { throw RecoveryEvidenceError.bounds }
            let offset = UInt32(position), bytes = Data(name.utf8)
            guard bytes.count <= Int(UInt16.max) else { throw RecoveryEvidenceError.bounds }
            var header = Data()
            header.put(UInt32(0x04034b50)); header.put(UInt16(20)); header.put(UInt16(0x0808)); header.put(UInt16(0))
            header.put(UInt16(0)); header.put(UInt16(0x0021)); header.put(UInt32(0)); header.put(UInt32(0)); header.put(UInt32(0))
            header.put(UInt16(bytes.count)); header.put(UInt16(0)); header.append(bytes)
            try write(header); return offset
        }
        private func end(_ name: String, offset: UInt32, crc: UInt32, size: UInt32) throws {
            var descriptor = Data(); descriptor.put(UInt32(0x08074b50)); descriptor.put(crc); descriptor.put(size); descriptor.put(size)
            try write(descriptor)
            let bytes = Data(name.utf8)
            central.put(UInt32(0x02014b50)); central.put(UInt16(20)); central.put(UInt16(20)); central.put(UInt16(0x0808)); central.put(UInt16(0))
            central.put(UInt16(0)); central.put(UInt16(0x0021)); central.put(crc); central.put(size); central.put(size)
            central.put(UInt16(bytes.count)); central.put(UInt16(0)); central.put(UInt16(0)); central.put(UInt16(0)); central.put(UInt16(0))
            central.put(UInt32(name.hasSuffix("/") ? 0x10 : 0)); central.put(offset); central.append(bytes)
            guard central.count <= 16 * 1024 * 1024 else { throw RecoveryEvidenceError.bounds }
            entries += 1
        }
        func data(_ bytes: Data, name: String) throws {
            let offset = try begin(name)
            try write(bytes)
            try end(name, offset: offset, crc: Self.crc(bytes, seed: 0xffffffff) ^ 0xffffffff, size: UInt32(bytes.count))
        }
        func file(_ url: URL, name: String, expectedBytes: Int64) throws -> String {
            let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw RecoveryEvidenceError.unsafeEntry }
            let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true); defer { try? input.close() }
            var info = stat()
            guard fstat(descriptor, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_size == expectedBytes else { throw RecoveryEvidenceError.changed }
            let offset = try begin(name)
            var size: Int64 = 0, crc: UInt32 = 0xffffffff, hash = SHA256()
            while true {
                try Task.checkCancellation()
                let chunk = try input.read(upToCount: 1024 * 1024) ?? Data()
                if chunk.isEmpty { break }
                size += Int64(chunk.count); guard size <= expectedBytes else { throw RecoveryEvidenceError.changed }
                crc = Self.crc(chunk, seed: crc); hash.update(data: chunk); try write(chunk)
            }
            guard size == expectedBytes else { throw RecoveryEvidenceError.changed }
            try end(name, offset: offset, crc: crc ^ 0xffffffff, size: UInt32(size))
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        }
        func finish() throws {
            let start = UInt32(position); try write(central)
            var end = Data(); end.put(UInt32(0x06054b50)); end.put(UInt16(0)); end.put(UInt16(0)); end.put(entries); end.put(entries)
            end.put(UInt32(central.count)); end.put(start); end.put(UInt16(0)); try write(end)
            try handle.synchronize(); try handle.close(); closed = true
        }
        func verifyReadback(_ url: URL) throws {
            let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
            var hash = SHA256(), count: UInt64 = 0
            while true {
                try Task.checkCancellation()
                let bytes = try input.read(upToCount: 1024 * 1024) ?? Data()
                if bytes.isEmpty { break }
                count += UInt64(bytes.count); guard count <= position else { throw RecoveryEvidenceError.changed }
                hash.update(data: bytes)
            }
            guard count == position, hash.finalize() == outputHash.finalize() else { throw RecoveryEvidenceError.changed }
        }
        private static let table: [UInt32] = (0..<256).map { value in
            var crc = UInt32(value)
            for _ in 0..<8 { crc = crc >> 1 ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
            return crc
        }
        private static func crc(_ data: Data, seed: UInt32) -> UInt32 {
            var crc = seed
            for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
            return crc
        }
    }
}
private extension Data {
    mutating func put<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian; Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
