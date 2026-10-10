import Foundation
#if canImport(SkriptumCore)
import SkriptumCore
#endif

enum ICloudOwnerConnectionChoiceError: Error, Equatable { case invalid, superseded, accountChanged }

/// Device-local opt-in only. No document bodies, tokens, keys or CloudKit grants.
/// Revision-bearing disabled records prevent an old activation from resurrecting
/// a connection after a disconnect, including a nil -> disabled -> nil ABA.
@MainActor final class ICloudOwnerConnectionChoice {
    struct Selection: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let containerIdentifier: String
        let libraryID: UUID
        let revision: UUID
        let enabled: Bool
        let scope: ICloudSyncScope?
    }
    static let containerIdentifier = "iCloud.com.mobilebox.Skriptum"
    private let directory: URL
    private let libraryID: UUID
    var fileURL: URL { directory.appendingPathComponent("owner-connection-" + libraryID.uuidString.lowercased() + ".json") }
    init(directory: URL, libraryID: UUID) { self.directory = directory; self.libraryID = libraryID }
    func load() throws -> Selection? {
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        let files = try ICloudSyncEngine.Files(directory: directory, name: fileURL.lastPathComponent)
        guard let data = try files.read(maximum: 4096) else { return nil }
        let value = try JSONDecoder().decode(Selection.self, from: data)
        try validate(value); return value
    }
    func confirm(_ expected: Selection?) throws {
        guard try load() == expected else { throw ICloudOwnerConnectionChoiceError.superseded }
    }
    @discardableResult func enable(scope: ICloudSyncScope, replacing expected: Selection?) throws -> Selection {
        try confirm(expected)
        let value = Selection(schemaVersion: 1, containerIdentifier: Self.containerIdentifier,
            libraryID: libraryID, revision: UUID(), enabled: true, scope: scope)
        try write(value); return value
    }
    /// Explicit disconnect may repair a malformed local opt-in descriptor; it
    /// never edits a manuscript or deletes a durable upload/recovery checkpoint.
    func disable(lastKnownScope: ICloudSyncScope? = nil) throws {
        let previous = try? load()
        let value = Selection(schemaVersion: 1, containerIdentifier: Self.containerIdentifier,
            libraryID: libraryID, revision: UUID(), enabled: false, scope: previous?.scope ?? lastKnownScope)
        try write(value)
    }
    func admit(accountID: String, selection: Selection?, allowAccountChange: Bool = false) throws -> ICloudSyncScope {
        if let selection { try validate(selection) }
        if let previous = selection?.scope, !allowAccountChange,
           !previous.accountID.utf8.elementsEqual(accountID.utf8) { throw ICloudOwnerConnectionChoiceError.accountChanged }
        return try ICloudSyncScope(accountID: accountID, libraryID: libraryID)
    }
    private func validate(_ value: Selection) throws {
        guard value.schemaVersion == 1, value.containerIdentifier == Self.containerIdentifier,
              value.libraryID == libraryID, !value.enabled || value.scope != nil else { throw ICloudOwnerConnectionChoiceError.invalid }
        if let scope = value.scope {
            _ = try ICloudSyncScope(accountID: scope.accountID, libraryID: scope.libraryID)
            guard scope.libraryID == libraryID else { throw ICloudOwnerConnectionChoiceError.invalid }
        }
    }
    private func write(_ value: Selection) throws {
        try validate(value)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(value)
        guard bytes.count <= 4096 else { throw ICloudOwnerConnectionChoiceError.invalid }
        let files = try ICloudSyncEngine.Files(directory: directory, name: fileURL.lastPathComponent, createParents: true)
        try files.write(bytes)
    }
}
