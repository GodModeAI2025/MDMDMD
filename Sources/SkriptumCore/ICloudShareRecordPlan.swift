import Foundation

/// A share owns an explicit hierarchy. Image aliases prevent one immutable asset
/// used on private and shared pages from pulling an unrelated page into a share.
public struct ICloudShareRecordPlan: Sendable {
    public struct Entry: Equatable, Sendable {
        public let recordName: String
        public let source: ICloudSyncRecordID
        public let parentRecordName: String?
        public let isImageAlias: Bool
    }
    public let rootRecordName: String
    public let entries: [Entry]

    @MainActor public init(scope: ICloudShareScope, snapshot: LibrarySnapshot) throws {
        let manifest = try ICloudShareManifest(scope: scope, snapshot: snapshot)
        func name(_ id: ICloudSyncRecordID) -> String { id.kind.rawValue + ":" + id.id.uuidString.lowercased() }
        rootRecordName = name(manifest.root)
        let rootName = rootRecordName
        var result = [Entry(recordName: rootName, source: manifest.root, parentRecordName: nil, isImageAlias: false)]
        for id in manifest.pages.sorted(by: { $0.uuidString < $1.uuidString }) {
            let source = ICloudSyncRecordID(kind: .page, id: id)
            if source != manifest.root {
                let page = snapshot.pages.first { $0.id == id }
                let parent = page?.parentID.map { "page:" + $0.uuidString.lowercased() } ?? rootName
                result.append(Entry(recordName: name(source), source: source, parentRecordName: parent, isImageAlias: false))
            }
        }
        for (kind, ids) in [(ICloudSyncRecordKind.comment, manifest.comments), (.revision, manifest.revisions)] {
            for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
                let source = ICloudSyncRecordID(kind: kind, id: id)
                let pageID = kind == .comment ? snapshot.comments.first(where: { $0.id == id })?.pageID
                    : snapshot.revisions.first(where: { $0.id == id })?.page.id
                guard let pageID else { throw LibraryError.invalidLibrary }
                result.append(Entry(recordName: name(source), source: source,
                    parentRecordName: "page:" + pageID.uuidString.lowercased(), isImageAlias: false))
            }
        }
        for id in manifest.images.sorted(by: { $0.uuidString < $1.uuidString }) {
            let source = ICloudSyncRecordID(kind: .image, id: id)
            // CloudKit parent is singular. Keep the private canonical asset
            // outside all shares; each share has a stable dedicated alias.
            result.append(Entry(recordName: "shared-image:" + rootName + ":" + id.uuidString.lowercased(),
                source: source, parentRecordName: rootName, isImageAlias: true))
        }
        entries = result
    }
}
