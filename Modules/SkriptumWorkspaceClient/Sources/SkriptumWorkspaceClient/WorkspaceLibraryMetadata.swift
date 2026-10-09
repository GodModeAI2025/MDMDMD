import Foundation

/// Authorized server metadata, not a credential or ongoing permission grant.
public struct WorkspaceLibraryMetadata: Equatable, Sendable {
    public let libraryID: UUID
    public let title: String
    public let role: WorkspaceRole
}
public struct WorkspaceLibraryMetadataPage: Equatable, Sendable {
    public let libraries: [WorkspaceLibraryMetadata]
    public let nextAfter: UUID?
}

enum WorkspaceLibraryWire {
    static let maximumBytes = 256 * 1024
    static func metadata(_ data: Data, expectedID: UUID) throws -> WorkspaceLibraryMetadata {
        guard data.count <= maximumBytes else { throw WorkspaceClientError.invalidResponse }
        let value = try row(WorkspaceWire.object(data, keys: ["libraryID", "title", "role"]))
        guard value.libraryID == expectedID else { throw WorkspaceClientError.invalidResponse }
        return value
    }
    static func page(_ data: Data, after: UUID?) throws -> WorkspaceLibraryMetadataPage {
        guard data.count <= maximumBytes else { throw WorkspaceClientError.invalidResponse }
        let object = try WorkspaceWire.object(data, keys: ["libraries", "nextAfter"], allowsSmallArrays: true)
        guard let rows = object["libraries"] as? [[String: Any]], rows.count <= 8 else { throw WorkspaceClientError.invalidResponse }
        var libraries: [WorkspaceLibraryMetadata] = []
        var last = after
        for object in rows {
            let value = try row(object)
            guard last.map({ ordered(value.libraryID, after: $0) }) ?? true else { throw WorkspaceClientError.invalidResponse }
            libraries.append(value); last = value.libraryID
        }
        let cursor: UUID?
        if object["nextAfter"] is NSNull { cursor = nil }
        else {
            let value = try WorkspaceWire.uuid(object["nextAfter"])
            guard after.map({ ordered(value, after: $0) }) ?? true,
                  last.map({ value == $0 || ordered(value, after: $0) }) ?? true else { throw WorkspaceClientError.invalidResponse }
            cursor = value
        }
        return WorkspaceLibraryMetadataPage(libraries: libraries, nextAfter: cursor)
    }
    private static func row(_ object: [String: Any]) throws -> WorkspaceLibraryMetadata {
        guard Set(object.keys) == ["libraryID", "title", "role"],
              let title = object["title"] as? String, (1...4096).contains(title.utf8.count),
              let name = object["role"] as? String, let role = WorkspaceRole(rawValue: name), role != .none else {
            throw WorkspaceClientError.invalidResponse
        }
        return WorkspaceLibraryMetadata(libraryID: try WorkspaceWire.uuid(object["libraryID"]), title: title, role: role)
    }
    private static func ordered(_ value: UUID, after: UUID) -> Bool {
        value.uuidString.lowercased() > after.uuidString.lowercased()
    }
}
