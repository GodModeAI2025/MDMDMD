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
