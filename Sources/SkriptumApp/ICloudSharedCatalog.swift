import Foundation
#if canImport(SkriptumCore)
import SkriptumCore
#endif

/// Local discovery descriptors only: never document bodies, credentials or grants.
@MainActor final class ICloudSharedCatalog {
    struct Entry: Codable, Identifiable {
        var id: ICloudSharedStoreIdentity { identity }
        let identity: ICloudSharedStoreIdentity
        let titlePreview: String
        let lastOpened: Date
    }
    private struct Snapshot: Codable { var schemaVersion = 1; var entries: [Entry] = [] }
    private let files: ICloudSyncEngine.Files
    init(directory: URL) throws {
        files = try ICloudSyncEngine.Files(directory: directory, name: "shared-catalog-v1.json", createParents: true)
    }
    func entries(accountID: String) throws -> [Entry] {
        try load().entries.filter { $0.identity.accountID.utf8.elementsEqual(accountID.utf8) }
            .sorted { $0.lastOpened > $1.lastOpened }
    }
    func record(_ identity: ICloudSharedStoreIdentity, title: String) throws {
        var snapshot = try load()
        snapshot.entries.removeAll { $0.identity == identity }
        // A bounded display preview; canonical document titles remain unchanged.
        let preview = String(String.UnicodeScalarView(title.unicodeScalars.prefix(256)))
        snapshot.entries.append(Entry(identity: identity, titlePreview: preview, lastOpened: Date()))
        try persist(snapshot)
    }
    func remove(_ identity: ICloudSharedStoreIdentity) throws {
        var snapshot = try load(); snapshot.entries.removeAll { $0.identity == identity }; try persist(snapshot)
    }
    private func load() throws -> Snapshot {
        guard let data = try files.read() else { return Snapshot() }
        let value = try JSONDecoder().decode(Snapshot.self, from: data)
        try validate(value); return value
    }
    private func persist(_ value: Snapshot) throws {
        try validate(value)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try files.write(encoder.encode(value))
    }
    private func validate(_ value: Snapshot) throws {
        guard value.schemaVersion == 1, value.entries.count <= 4096,
              Set(value.entries.map(\.identity)).count == value.entries.count else { throw ICloudSharedStoreError.invalidCheckpoint }
        for entry in value.entries {
            let id = entry.identity
            _ = try ICloudSharedStoreIdentity(accountID: id.accountID, ownerID: id.ownerID,
                zoneName: id.zoneName, shareName: id.shareName, root: id.root)
            guard entry.titlePreview.unicodeScalars.count <= 256 else { throw ICloudSharedStoreError.invalidCheckpoint }
        }
    }
}
