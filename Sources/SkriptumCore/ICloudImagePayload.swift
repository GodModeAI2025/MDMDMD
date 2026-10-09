import Foundation
import Darwin

public enum ICloudImagePayloadError: Error, Equatable, Sendable {
    case invalidPayload, invalidIdentity, unsafeStorage, existingMismatch, persistence
}

/// Image bytes are a raw binary body for CKAsset, never JSON/base64. The frame
/// supports the existing 32 MiB media contract; transport integration must grant
/// that budget specifically to .image records before claiming large-image sync.
public struct ICloudImagePayload: Sendable, CustomStringConvertible, CustomReflectable {
    public let attachment: MediaAttachment
    public let revisionID: UUID
    public let data: Data
    public static let maximumHeaderBytes = 8192
    public static let maximumEncodedBytes = MediaValidation.maximumBytes + maximumHeaderBytes + 4
    private struct Header: Codable {
        let schemaVersion: Int
        let attachment: MediaAttachment
        let revisionID: UUID
    }
    public init(attachment: MediaAttachment, revisionID: UUID, data: Data) throws {
        guard (1...1024).contains(attachment.filename.utf8.count),
              !attachment.filename.contains("/"), !attachment.filename.contains("\\"),
              attachment.filename != ".", attachment.filename != "..",
              attachment.byteCount == data.count, attachment.sha256 == MediaValidation.digest(data) else {
            throw ICloudImagePayloadError.invalidPayload
        }
        try MediaValidation.validate(data, mediaType: attachment.mediaType)
        self.attachment = attachment; self.revisionID = revisionID; self.data = data
    }
    public var description: String { "ICloudImagePayload(<private image bytes>)" }
    public var customMirror: Mirror { Mirror(self, children: ["image": "<private>"]) }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let header = try encoder.encode(Header(schemaVersion: 1, attachment: attachment, revisionID: revisionID))
        guard header.count <= Self.maximumHeaderBytes else { throw ICloudImagePayloadError.invalidPayload }
        let length = UInt32(header.count)
        var frame = Data([UInt8((length >> 24) & 255), UInt8((length >> 16) & 255), UInt8((length >> 8) & 255), UInt8(length & 255)])
        frame.append(header); frame.append(data)
        return frame
    }
    public static func decode(_ frame: Data, expectedImageID: UUID, expectedRevision: UUID) throws -> Self {
        guard frame.count >= 4, frame.count <= maximumEncodedBytes else { throw ICloudImagePayloadError.invalidPayload }
        let bytes = Array(frame.prefix(4))
        let length = bytes.reduce(0) { ($0 << 8) | Int($1) }
        guard (1...maximumHeaderBytes).contains(length), length <= frame.count - 4 else { throw ICloudImagePayloadError.invalidPayload }
        let header = try JSONDecoder().decode(Header.self, from: frame.subdata(in: 4..<(4 + length)))
        guard header.schemaVersion == 1 else { throw ICloudImagePayloadError.invalidPayload }
        guard header.attachment.id == expectedImageID, header.revisionID == expectedRevision else { throw ICloudImagePayloadError.invalidIdentity }
        return try Self(attachment: header.attachment, revisionID: header.revisionID, data: frame.subdata(in: (4 + length)..<frame.count))
    }
    static func descriptorsMatch(_ a: MediaAttachment, _ b: MediaAttachment) -> Bool {
        a.id == b.id && a.byteCount == b.byteCount && a.filename.utf8.elementsEqual(b.filename.utf8)
            && a.mediaType.utf8.elementsEqual(b.mediaType.utf8) && a.sha256.utf8.elementsEqual(b.sha256.utf8)
    }
}

extension LibraryStore {
    /// Stages immutable bytes before page merge; does not mutate document state.
    /// Existing IDs are idempotent only for exact already-validated bytes.
    @discardableResult public func importICloudImage(_ payload: ICloudImagePayload) throws -> MediaAttachment {
        let attachment = payload.attachment
        _ = try ICloudImagePayload(attachment: attachment, revisionID: payload.revisionID, data: payload.data)
        for known in (snapshot.pages + snapshot.revisions.map(\.page)).flatMap({ $0.attachments ?? [] }) where known.id == attachment.id {
            guard ICloudImagePayload.descriptorsMatch(known, attachment) else { throw ICloudImagePayloadError.existingMismatch }
        }
        let root = try ICloudImageFiles.openOwnedDirectory(directory)
        defer { Darwin.close(root) }
        var media = Darwin.openat(root, "media", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if media < 0, errno == ENOENT {
            if Darwin.mkdirat(root, "media", 0o700) != 0, errno != EEXIST { throw ICloudImagePayloadError.persistence }
            media = Darwin.openat(root, "media", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard media >= 0 else { throw ICloudImagePayloadError.unsafeStorage }
        defer { Darwin.close(media) }
        var info = stat()
        guard Darwin.fstat(media, &info) == 0, info.st_uid == getuid() else { throw ICloudImagePayloadError.unsafeStorage }
        let final = attachment.id.uuidString
        if try ICloudImageFiles.existingMatches(media, name: final, payload: payload) { return attachment }
        let temporary = ".icloud-image-" + UUID().uuidString
        let staged = Darwin.openat(media, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard staged >= 0 else { throw ICloudImagePayloadError.persistence }
        defer { Darwin.close(staged); Darwin.unlinkat(media, temporary, 0) }
        try payload.data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(staged, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw ICloudImagePayloadError.persistence }; offset += count
            }
        }
        guard Darwin.fsync(staged) == 0 else { throw ICloudImagePayloadError.persistence }
        guard try ICloudImageFiles.existingMatches(media, name: temporary, payload: payload) else { throw ICloudImagePayloadError.persistence }
        // linkat is exclusive: an existing target, including a symbolic link,
        // is never replaced. Concurrent creation is checked rather than erased.
        if Darwin.linkat(media, temporary, media, final, 0) != 0 {
            guard errno == EEXIST, try ICloudImageFiles.existingMatches(media, name: final, payload: payload) else { throw ICloudImagePayloadError.persistence }
        }
        guard Darwin.unlinkat(media, temporary, 0) == 0, Darwin.fsync(media) == 0, Darwin.fsync(root) == 0 else { throw ICloudImagePayloadError.persistence }
        guard try ICloudImageFiles.existingMatches(media, name: final, payload: payload) else { throw ICloudImagePayloadError.persistence }
        return attachment
    }
}

private enum ICloudImageFiles {
    static func openOwnedDirectory(_ url: URL) throws -> Int32 {
        guard url.isFileURL, url.path.hasPrefix("/") else { throw ICloudImagePayloadError.unsafeStorage }
        let parts = url.path.split(separator: "/").map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ $0 != "." && $0 != ".." }) else { throw ICloudImagePayloadError.unsafeStorage }
        var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard current >= 0 else { throw ICloudImagePayloadError.persistence }
        for part in parts {
            let next = Darwin.openat(current, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            Darwin.close(current)
            guard next >= 0 else { throw ICloudImagePayloadError.unsafeStorage }; current = next
        }
        var info = stat()
        guard Darwin.fstat(current, &info) == 0, info.st_uid == getuid() else { Darwin.close(current); throw ICloudImagePayloadError.unsafeStorage }
        return current
    }
    static func existingMatches(_ directory: Int32, name: String, payload: ICloudImagePayload) throws -> Bool {
        let fd = Darwin.openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0, errno == ENOENT { return false }
        guard fd >= 0 else { throw ICloudImagePayloadError.unsafeStorage }
        defer { Darwin.close(fd) }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_uid == getuid(), info.st_nlink == 1, info.st_size == payload.attachment.byteCount,
              info.st_size <= MediaValidation.maximumBytes else { throw ICloudImagePayloadError.existingMismatch }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0, count <= payload.data.count - bytes.count else { throw ICloudImagePayloadError.existingMismatch }
            if count == 0 { break }; bytes.append(contentsOf: buffer.prefix(count))
        }
        guard bytes == payload.data, MediaValidation.digest(bytes) == payload.attachment.sha256 else { throw ICloudImagePayloadError.existingMismatch }
        try MediaValidation.validate(bytes, mediaType: payload.attachment.mediaType)
        return true
    }
}
