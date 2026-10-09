import Foundation
import CryptoKit

public enum LibraryStoragePathError: Error, Equatable, Sendable {
    case invalidURL, pathTraversal, outsideDocumentRoot, invalidOwnedLibrary
}

/// Pure path derivation for private, library-owned data. This helper performs no
/// filesystem access and never creates directories or falls back to another scope.
public enum LibraryStoragePaths {
    public static func assistantHistoryDirectory(libraryDirectory: URL, documentRoot: URL, applicationSupportRoot: URL) throws -> URL {
        let scope = try ownedScope(libraryDirectory: libraryDirectory, documentRoot: documentRoot)
        try validateFileURL(applicationSupportRoot)
        let privateRoot = applicationSupportRoot.appendingPathComponent("Skriptum", isDirectory: true)
        if scope == "Skriptum" { return privateRoot.appendingPathComponent("Chats", isDirectory: true) }
        let digest = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        return privateRoot.appendingPathComponent("LibraryChats", isDirectory: true).appendingPathComponent(digest, isDirectory: true)
    }

    public static func recoveriesDirectory(libraryDirectory: URL, documentRoot: URL) throws -> URL {
        _ = try ownedScope(libraryDirectory: libraryDirectory, documentRoot: documentRoot)
        return libraryDirectory.appendingPathComponent("Recoveries", isDirectory: true)
    }

    private static func validateFileURL(_ url: URL) throws {
        guard url.isFileURL, url.baseURL == nil, url.path.hasPrefix("/"),
              url.host == nil || url.host == "" || url.host == "localhost",
              url.query == nil, url.fragment == nil else { throw LibraryStoragePathError.invalidURL }
        guard !url.pathComponents.contains("."), !url.pathComponents.contains(".."),
              !url.path.contains("\0") else { throw LibraryStoragePathError.pathTraversal }
    }

    private static func ownedScope(libraryDirectory: URL, documentRoot: URL) throws -> String {
        try validateFileURL(libraryDirectory); try validateFileURL(documentRoot)
        let root = documentRoot.pathComponents
        let library = libraryDirectory.pathComponents
        guard library.count > root.count, Array(library.prefix(root.count)) == root else { throw LibraryStoragePathError.outsideDocumentRoot }
        let relative = Array(library.dropFirst(root.count))
        if relative == ["Skriptum"] { return "Skriptum" }
        guard relative.count == 2, relative[0] == "ScriptumLibraries",
              let id = UUID(uuidString: relative[1]) else { throw LibraryStoragePathError.invalidOwnedLibrary }
        return "ScriptumLibraries/" + id.uuidString
    }
}

/// Durable scene scope contains no path or remote authority.
public enum OwnedLibraryLocator: Hashable, Sendable, Codable {
    case primary
    case imported(UUID)
    private enum Keys: String, CodingKey { case schemaVersion, kind, id }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == 1 else { throw LibraryStoragePathError.invalidOwnedLibrary }
        switch try values.decode(String.self, forKey: .kind) {
        case "primary":
            guard !values.contains(.id) else { throw LibraryStoragePathError.invalidOwnedLibrary }
            self = .primary
        case "imported": self = .imported(try values.decode(UUID.self, forKey: .id))
        default: throw LibraryStoragePathError.invalidOwnedLibrary
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        try values.encode(1, forKey: .schemaVersion)
        switch self {
        case .primary: try values.encode("primary", forKey: .kind)
        case .imported(let id): try values.encode("imported", forKey: .kind); try values.encode(id, forKey: .id)
        }
    }
}

public extension LibraryStoragePaths {
    static func locator(libraryDirectory: URL, documentRoot: URL) throws -> OwnedLibraryLocator {
        let scope = try ownedScope(libraryDirectory: libraryDirectory, documentRoot: documentRoot)
        if scope == "Skriptum" { return .primary }
        guard let id = UUID(uuidString: String(scope.dropFirst("ScriptumLibraries/".count))) else { throw LibraryStoragePathError.invalidOwnedLibrary }
        return .imported(id)
    }
    static func libraryDirectory(locator: OwnedLibraryLocator, documentRoot: URL) throws -> URL {
        try validateFileURL(documentRoot)
        switch locator {
        case .primary: return documentRoot.appendingPathComponent("Skriptum", isDirectory: true)
        case .imported(let id): return documentRoot.appendingPathComponent("ScriptumLibraries", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
        }
    }
}
