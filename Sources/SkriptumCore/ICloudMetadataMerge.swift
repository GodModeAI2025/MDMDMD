import Foundation

public enum ICloudMetadataMergeOutcome: Equatable, Sendable {
    case inserted, advanced, unchanged, conflict, pendingTombstone
}

/// The caller must retain conflict, pending tombstone and failed payloads in its
/// durable incoming inbox. This helper never acknowledges or discards that inbox.
@MainActor public enum ICloudMetadataMerge {
    @discardableResult public static func apply(_ change: ICloudSyncChange, to store: LibraryStore) throws -> ICloudMetadataMergeOutcome {
        guard [.space, .comment, .revision].contains(change.recordID.kind) else { throw ICloudMetadataMergeError.unsupportedKind }
        guard !store.hasActiveEdits else { throw LibraryError.editInProgress }
        if change.operation == .tombstone {
            guard change.payload.isEmpty else { throw ICloudMetadataMergeError.invalidPayload }
            // An empty tombstone carries no usable metadata ancestry. Never infer
            // permission to hard-delete a space, comment or historical revision.
            return .pendingTombstone
        }
        var candidate = store.snapshot
        let outcome: ICloudMetadataMergeOutcome
        switch change.recordID.kind {
        case .space: outcome = try merge(change, values: &candidate.spaces)
        case .comment: outcome = try merge(change, values: &candidate.comments)
        case .revision: outcome = try merge(change, values: &candidate.revisions, immutable: true)
        default: throw ICloudMetadataMergeError.unsupportedKind
        }
        if outcome == .inserted || outcome == .advanced {
            // Real library validation checks IDs, links, historical metadata and
            // ordering constraints before any durable/local presentation change.
            try LibraryStore.validate(candidate)
            try store.commit(candidate)
        }
        return outcome
    }

    private static func merge<Value: Codable & Sendable & Identifiable>(_ change: ICloudSyncChange,
        values: inout [Value], immutable: Bool = false) throws -> ICloudMetadataMergeOutcome where Value.ID == UUID {
        let incoming = try ICloudMetadataPayload<Value>.decode(change.payload)
        guard incoming.value.id == change.recordID.id else { throw ICloudMetadataMergeError.identityMismatch }
        guard try incoming.revisionID() == change.revisionID else { throw ICloudMetadataMergeError.revisionMismatch }
        if let index = values.firstIndex(where: { $0.id == incoming.value.id }) {
            let current = values[index]
            if try ICloudMetadataPayload<Value>.valueBytes(current) == ICloudMetadataPayload<Value>.valueBytes(incoming.value) { return .unchanged }
            guard !immutable else { throw ICloudMetadataMergeError.immutableRevision }
            guard try incoming.baseDigest == ICloudMetadataPayload<Value>.digest(of: current) else { return .conflict }
            values[index] = incoming.value
            return .advanced
        }
        guard incoming.baseDigest == nil else { return .conflict }
        values.append(incoming.value)
        return .inserted
    }
}
