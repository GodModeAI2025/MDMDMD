import Foundation
import Automerge

/// Exclusive owner of a real Automerge document. No mutable document escapes.
public actor PageReplica {
    public let identity: ReplicaIdentity
    public let limits: ReplicaLimits
    private var document: Document

    public init(identity: ReplicaIdentity, blocks: [ReplicaSeedBlock], limits: ReplicaLimits = ReplicaLimits()) throws {
        try Self.validateLimits(limits)
        self.identity = identity; self.limits = limits
        let doc = Document(textEncoding: .utf16)
        try doc.put(obj: .ROOT, key: "schemaVersion", value: .Uint(1))
        try doc.put(obj: .ROOT, key: "libraryID", value: .String(identity.libraryID.uuidString))
        try doc.put(obj: .ROOT, key: "spaceID", value: .String(identity.spaceID.uuidString))
        try doc.put(obj: .ROOT, key: "pageID", value: .String(identity.pageID.uuidString))
        let records = try doc.putObject(obj: .ROOT, key: "blocks", ty: .Map)
        guard blocks.count <= limits.maximumBlocks else { throw ReplicaError.limitExceeded }
        var seen: Set<UUID> = [], anchor: UUID?
        for seed in blocks {
            guard seen.insert(seed.id).inserted else { throw ReplicaError.duplicateBlock }
            try Self.add(seed, after: anchor, priority: 0, document: doc, records: records); anchor = seed.id
        }
        doc.commitWith(message: "Create page replica")
        _ = try Self.inspect(doc, identity: identity, limits: limits)
        guard doc.save().count <= limits.maximumSavedBytes else { throw ReplicaError.limitExceeded }
        document = doc
    }
    public init(identity: ReplicaIdentity, saved: Data, limits: ReplicaLimits = ReplicaLimits()) throws {
        try Self.validateLimits(limits)
        guard saved.count <= limits.maximumSavedBytes else { throw ReplicaError.limitExceeded }
        self.identity = identity; self.limits = limits
        // Upstream Document(bytes:) uses Rust AutoCommit.load's default encoding.
        // Apply the actual saved document into an explicitly UTF-16 document.
        let doc = Document(textEncoding: .utf16)
        let loaded = try Document(saved)
        try doc.merge(other: loaded)
        _ = try Self.inspect(doc, identity: identity, limits: limits)
        guard doc.save().count <= limits.maximumSavedBytes else { throw ReplicaError.limitExceeded }
        document = doc
    }
    private init(identity: ReplicaIdentity, limits: ReplicaLimits, document: Document) { self.identity = identity; self.limits = limits; self.document = document }
    public func fork() -> PageReplica { PageReplica(identity: identity, limits: limits, document: document.fork()) }
    public func snapshot() throws -> ReplicaSnapshot { try Self.inspect(document, identity: identity, limits: limits).snapshot }
    public func save() throws -> Data { let data = document.save(); guard data.count <= limits.maximumSavedBytes else { throw ReplicaError.limitExceeded }; return data }
    public func changes(since version: ReplicaVersion? = nil) throws -> Data {
        let heads: Set<ChangeHash>
        if let version { guard version.heads.count <= 32 * limits.maximumBlocks, let decoded = version.heads.heads() else { throw ReplicaError.invalidVersion }; heads = decoded }
        else { heads = [] }
        let data = try document.encodeChangesSince(heads: heads)
        guard data.count <= limits.maximumIncomingBytes else { throw ReplicaError.limitExceeded }
        return data
    }
    public func receive(_ data: Data) throws {
        guard data.count <= limits.maximumIncomingBytes else { throw ReplicaError.limitExceeded }
        if data.isEmpty { return }
        // The upstream incremental loader explicitly permits partial loads.
        // Strict-load the complete accepted save plus all incoming chunks first;
        // this rejects malformed trailing data instead of publishing its prefix.
        var complete = document.save(); complete.append(data)
        let strict = try Document(complete)
        let candidate = document.fork(); candidate.actor = document.actor
        try candidate.merge(other: strict)
        try publish(candidate)
    }
    public func edit(blockID: UUID, range: UTF16Range, replacement: String) throws {
        let state = try Self.inspect(document, identity: identity, limits: limits)
        guard let record = state.records[blockID] else { throw ReplicaError.missingBlock }
        guard !record.deleted else { throw ReplicaError.deletedBlock }
        let current = try document.text(obj: record.text)
        try Self.validateRange(range, in: current)
        guard replacement.utf8.count <= limits.maximumTextBytes else { throw ReplicaError.limitExceeded }
        if range.length == 0 && replacement.isEmpty { return }
        let candidate = document.fork(); candidate.actor = document.actor
        try candidate.spliceText(obj: record.text, start: UInt64(range.location), delete: Int64(range.length), value: replacement)
        try candidate.increment(obj: record.object, key: "editCount", by: 1)
        candidate.commitWith(message: "Edit block \(blockID.uuidString)")
        try publish(candidate)
    }
    public func insert(_ block: ReplicaSeedBlock, after anchor: UUID?) throws {
        let state = try Self.inspect(document, identity: identity, limits: limits)
        guard state.records[block.id] == nil else { throw ReplicaError.duplicateBlock }
        if let anchor, state.records[anchor] == nil { throw ReplicaError.missingBlock }
        let candidate = document.fork(); candidate.actor = document.actor
        try Self.add(block, after: anchor, priority: try state.nextPriority(), document: candidate, records: state.container)
        candidate.commitWith(message: "Insert block \(block.id.uuidString)")
        try publish(candidate)
    }
    public func delete(blockID: UUID) throws {
        let state = try Self.inspect(document, identity: identity, limits: limits)
        guard let record = state.records[blockID] else { throw ReplicaError.missingBlock }
        guard !record.deleted else { return }
        let candidate = document.fork(); candidate.actor = document.actor
        try candidate.put(obj: record.object, key: "deletedAtEditCount", value: .Int(record.editCount))
        try candidate.put(obj: record.object, key: "deleted", value: .Boolean(true))
        candidate.commitWith(message: "Tombstone block \(blockID.uuidString)")
        try publish(candidate)
    }
    public func restore(blockID: UUID) throws {
        let state = try Self.inspect(document, identity: identity, limits: limits)
        guard let record = state.records[blockID] else { throw ReplicaError.missingBlock }
        let candidate = document.fork(); candidate.actor = document.actor
        try candidate.put(obj: record.object, key: "deleted", value: .Boolean(false))
        try candidate.put(obj: record.object, key: "deletedAtEditCount", value: .Int(record.editCount))
        candidate.commitWith(message: "Restore block \(blockID.uuidString)")
        try publish(candidate)
    }
    public func move(blockID: UUID, after anchor: UUID?) throws {
        guard blockID != anchor else { throw ReplicaError.invalidOrder }
        let state = try Self.inspect(document, identity: identity, limits: limits)
        guard let record = state.records[blockID] else { throw ReplicaError.missingBlock }
        if let anchor, state.records[anchor] == nil { throw ReplicaError.missingBlock }
        let candidate = document.fork(); candidate.actor = document.actor
        // Detach the old successor chain before inserting at the new position.
        // Concurrent writes remain Automerge map conflicts, never hidden drops.
        for child in state.records.values where child.anchor == blockID {
            try candidate.put(obj: child.object, key: "after", value: .String(record.anchor?.uuidString ?? ""))
        }
        try candidate.put(obj: record.object, key: "after", value: .String(anchor?.uuidString ?? ""))
        try candidate.put(obj: record.object, key: "priority", value: .Uint(state.nextPriority()))
        candidate.commitWith(message: "Move block \(blockID.uuidString)")
        try publish(candidate)
    }
    private func publish(_ candidate: Document) throws {
        let accepted = try Self.inspect(document, identity: identity, limits: limits)
        let inspected = try Self.inspect(candidate, identity: identity, limits: limits)
        // ObjId includes an actor-index hint that can change when loading a
        // merged save. Resolve historical IDs inside the candidate's own actor
        // table instead of comparing raw IDs from two different documents.
        let heads = document.heads()
        let historicalContainer = try Self.historicalObject(candidate, object: .ROOT, key: "blocks", heads: heads, type: .Map)
        guard historicalContainer == inspected.container else { throw ReplicaError.invalidSchema }
        for (id, old) in accepted.records {
            guard let new = inspected.records[id] else { throw ReplicaError.invalidSchema }
            let historicalRecord = try Self.historicalObject(candidate, object: historicalContainer, key: id.uuidString, heads: heads, type: .Map)
            let historicalText = try Self.historicalObject(candidate, object: historicalRecord, key: "text", heads: heads, type: .Text)
            guard new.object == historicalRecord, new.text == historicalText else { throw ReplicaError.invalidSchema }
            if !old.markdown.utf8.elementsEqual(new.markdown.utf8), new.editCount <= old.editCount { throw ReplicaError.invalidSchema }
        }
        guard candidate.save().count <= limits.maximumSavedBytes else { throw ReplicaError.limitExceeded }
        document = candidate
    }
    private static func historicalObject(_ document: Document, object: ObjId, key: String, heads: Set<ChangeHash>, type: ObjType) throws -> ObjId {
        let values = try document.getAllAt(obj: object, key: key, heads: heads)
        guard values.count == 1, case .Object(let id, let actual)? = values.first, actual == type else { throw ReplicaError.invalidSchema }
        return id
    }
    private static func add(_ seed: ReplicaSeedBlock, after anchor: UUID?, priority: UInt64, document: Document, records: ObjId) throws {
        let record = try document.putObject(obj: records, key: seed.id.uuidString, ty: .Map)
        try document.put(obj: record, key: "id", value: .String(seed.id.uuidString))
        let text = try document.putObject(obj: record, key: "text", ty: .Text)
        try document.spliceText(obj: text, start: 0, delete: 0, value: seed.markdown)
        try document.put(obj: record, key: "editCount", value: .Counter(0))
        try document.put(obj: record, key: "deleted", value: .Boolean(false))
        try document.put(obj: record, key: "deletedAtEditCount", value: .Int(0))
        try document.put(obj: record, key: "after", value: .String(anchor?.uuidString ?? ""))
        try document.put(obj: record, key: "priority", value: .Uint(priority))
    }
    private static func validateLimits(_ limits: ReplicaLimits) throws {
        guard limits.maximumIncomingBytes > 0, limits.maximumSavedBytes > 0, limits.maximumTextBytes > 0, limits.maximumBlocks > 0, limits.maximumBlocks <= 100_000 else { throw ReplicaError.limitExceeded }
    }
    private static func validateRange(_ range: UTF16Range, in text: String) throws {
        let units = Array(text.utf16)
        guard range.location >= 0, range.length >= 0, range.location <= units.count, range.length <= units.count - range.location else { throw ReplicaError.invalidUTF16Range }
        for boundary in [range.location, range.location + range.length] where boundary > 0 && boundary < units.count {
            if (0xD800...0xDBFF).contains(units[boundary - 1]) && (0xDC00...0xDFFF).contains(units[boundary]) { throw ReplicaError.invalidUTF16Range }
        }
    }
}
