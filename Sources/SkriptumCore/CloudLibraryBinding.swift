import Foundation
import Darwin

public enum CloudLibraryBindingError: Error, Equatable, Sendable {
    case invalidRecord, wrongLocator, conflict, oversized, unsafeFile, persistence
}

/// Non-secret local mapping only. Neither this record nor its UUIDs confer server rights.
public struct CloudLibraryBinding: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let locator: OwnedLibraryLocator
    public let origin: String
    public let profileID: String
    public let accountID: UUID
    public let remoteLibraryID: UUID
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, locator, origin, profileID, accountID, remoteLibraryID
    }
    private struct RawKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.container(keyedBy: RawKey.self)
        guard Set(raw.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)) else { throw CloudLibraryBindingError.invalidRecord }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        locator = try values.decode(OwnedLibraryLocator.self, forKey: .locator)
        origin = try values.decode(String.self, forKey: .origin)
        profileID = try values.decode(String.self, forKey: .profileID)
        accountID = try values.decode(UUID.self, forKey: .accountID)
        remoteLibraryID = try values.decode(UUID.self, forKey: .remoteLibraryID)
        try validate()
    }
    public init(locator: OwnedLibraryLocator, origin: String, profileID: String, accountID: UUID, remoteLibraryID: UUID) throws {
        schemaVersion = 1; self.locator = locator
        self.origin = try Self.canonicalOrigin(origin)
        self.profileID = profileID; self.accountID = accountID; self.remoteLibraryID = remoteLibraryID
        try validate()
    }
    private static func canonicalOrigin(_ value: String) throws -> String {
        guard value.utf8.count <= 2048, !value.contains("%"), !value.contains("\\"),
              !value.contains(where: { $0.isWhitespace }),
              var parts = URLComponents(string: value), parts.scheme == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/",
              parts.port.map({ (1...65535).contains($0) }) ?? true else { throw CloudLibraryBindingError.invalidRecord }
        parts.host = host.lowercased(); parts.path = ""
        if parts.port == 443 { parts.port = nil }
        guard let url = parts.url, url.host != nil else { throw CloudLibraryBindingError.invalidRecord }
        return url.absoluteString
    }
    public func validate() throws {
        guard schemaVersion == 1, origin == (try Self.canonicalOrigin(origin)),
              (1...64).contains(profileID.utf8.count),
              profileID.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0) }) else { throw CloudLibraryBindingError.invalidRecord }
    }
}

/// Process-local serialized CAS. Supply genuinely owned canonical container roots.
/// No cross-process locking, cloud connection or credential storage is implied.
public struct CloudLibraryBindingRepository: Sendable {
    public let locator: OwnedLibraryLocator
    public let fileURL: URL
    private static let transactionLock = NSLock()
    private static let maximumBytes = 8192
    public init(locator: OwnedLibraryLocator, documentRoot: URL, supportRoot: URL) throws {
        self.locator = locator
        let library = try LibraryStoragePaths.libraryDirectory(locator: locator, documentRoot: documentRoot)
        let scope = try LibraryStoragePaths.assistantHistoryDirectory(libraryDirectory: library, documentRoot: documentRoot, applicationSupportRoot: supportRoot)
        fileURL = scope.appendingPathComponent("CloudBinding", isDirectory: true).appendingPathComponent("binding.json")
    }
    private func encoded(_ value: CloudLibraryBinding) throws -> Data {
        try value.validate()
        guard value.locator == locator else { throw CloudLibraryBindingError.wrongLocator }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(value)
        guard bytes.count <= Self.maximumBytes else { throw CloudLibraryBindingError.oversized }
        return bytes
    }
    public func load() throws -> CloudLibraryBinding? {
        try Self.transactionLock.withLock { try read() }
    }
    public func save(_ value: CloudLibraryBinding, replacing expected: CloudLibraryBinding?) throws {
        try Self.transactionLock.withLock {
            let bytes = try encoded(value)
            guard try read() == expected else { throw CloudLibraryBindingError.conflict }
            try write(bytes)
        }
    }
    public func remove(expected: CloudLibraryBinding) throws {
        try Self.transactionLock.withLock {
            _ = try encoded(expected)
            guard try read() == expected else { throw CloudLibraryBindingError.conflict }
            guard let directory = try parent(create: false) else { throw CloudLibraryBindingError.conflict }
            defer { close(directory) }
            guard unlinkat(directory, fileURL.lastPathComponent, 0) == 0 else { throw ioError() }
        }
    }
    private func ioError() -> CloudLibraryBindingError {
        errno == ELOOP || errno == ENOTDIR ? .unsafeFile : .persistence
    }
    private func parent(create: Bool) throws -> Int32? {
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw ioError() }
        do {
            for component in fileURL.deletingLastPathComponent().pathComponents.dropFirst() {
                var next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                if next < 0 && errno == ENOENT && create {
                    guard mkdirat(descriptor, component, 0o700) == 0 || errno == EEXIST else { throw ioError() }
                    next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                if next < 0 {
                    if errno == ENOENT && !create { close(descriptor); return nil }
                    throw ioError()
                }
                close(descriptor); descriptor = next
            }
            return descriptor
        } catch { close(descriptor); throw error }
    }
    private func read() throws -> CloudLibraryBinding? {
        guard let directory = try parent(create: false) else { return nil }
        defer { close(directory) }
        let descriptor = openat(directory, fileURL.lastPathComponent, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw ioError()
        }
        defer { close(descriptor) }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0 else { throw ioError() }
        guard attributes.st_mode & S_IFMT == S_IFREG else { throw CloudLibraryBindingError.unsafeFile }
        guard attributes.st_size >= 0, attributes.st_size <= Self.maximumBytes else { throw CloudLibraryBindingError.oversized }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0 { if errno == EINTR { continue }; throw ioError() }
            if count == 0 { break }
            guard count <= Self.maximumBytes - bytes.count else { throw CloudLibraryBindingError.oversized }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        do {
            let value = try JSONDecoder().decode(CloudLibraryBinding.self, from: bytes)
            // Our versioned disk format is canonical sorted-key JSON. This also
            // rejects duplicate/unknown keys and aliases lost by JSONDecoder.
            guard try encoded(value) == bytes else { throw CloudLibraryBindingError.invalidRecord }
            return value
        } catch let error as CloudLibraryBindingError { throw error }
        catch { throw CloudLibraryBindingError.invalidRecord }
    }
    private func write(_ bytes: Data) throws {
        guard let directory = try parent(create: true) else { throw CloudLibraryBindingError.unsafeFile }
        defer { close(directory) }
        var attributes = stat()
        let status = fstatat(directory, fileURL.lastPathComponent, &attributes, AT_SYMLINK_NOFOLLOW)
        if status == 0 { guard attributes.st_mode & S_IFMT == S_IFREG else { throw CloudLibraryBindingError.unsafeFile } }
        else if errno != ENOENT { throw ioError() }
        let temporary = ".binding-" + UUID().uuidString + ".tmp"
        let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ioError() }
        defer { close(descriptor); unlinkat(directory, temporary, 0) }
        try bytes.withUnsafeBytes { payload in
            var offset = 0
            while offset < payload.count {
                let count = Darwin.write(descriptor, payload.baseAddress!.advanced(by: offset), payload.count - offset)
                if count < 0 { if errno == EINTR { continue }; throw ioError() }
                guard count > 0 else { throw CloudLibraryBindingError.persistence }; offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw ioError() }
        guard renameat(directory, temporary, directory, fileURL.lastPathComponent) == 0 else { throw ioError() }
        // Rename is the commit point; no subsequent throwable step.
    }
}
