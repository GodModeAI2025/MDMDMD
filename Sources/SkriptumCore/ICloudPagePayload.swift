import Foundation

/// Explicit ancestry travels with the page; modification timestamps never decide
/// which author's text survives a concurrent edit.
public struct ICloudPagePayload: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let page: Page
    public let baseRevision: UUID?
    public init(page: Page, baseRevision: UUID?) {
        schemaVersion = Self.version(for: page); self.page = page; self.baseRevision = baseRevision
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
    public static func decode(_ data: Data, expectedPageID: UUID, expectedRevision: UUID) throws -> Self {
        guard data.count <= 8 * 1024 * 1024 else { throw LibraryError.invalidLibrary }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == Self.version(for: value.page), value.page.id == expectedPageID,
              value.page.revision == expectedRevision else { throw LibraryError.invalidLibrary }
        return value
    }
    /// Older readers reject v2 before they can drop the alias and write back a
    /// page whose untouched Markdown no longer resolves to its image bytes.
    static func version(for page: Page) -> Int {
        page.attachments?.contains(where: { $0.sourcePath != nil }) == true ? 2 : 1
    }
}
