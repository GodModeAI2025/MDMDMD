import Foundation

/// Explicit ancestry travels with the page; modification timestamps never decide
/// which author's text survives a concurrent edit.
public struct ICloudPagePayload: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let page: Page
    public let baseRevision: UUID?
    public init(page: Page, baseRevision: UUID?) {
        schemaVersion = 1; self.page = page; self.baseRevision = baseRevision
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
    public static func decode(_ data: Data, expectedPageID: UUID, expectedRevision: UUID) throws -> Self {
        guard data.count <= 8 * 1024 * 1024 else { throw LibraryError.invalidLibrary }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == 1, value.page.id == expectedPageID,
              value.page.revision == expectedRevision else { throw LibraryError.invalidLibrary }
        return value
    }
}
