import Foundation
import Automerge

struct ReplicaRecord {
    let id: UUID
    let object: ObjId
    let text: ObjId
    let anchor: UUID?
    let priority: UInt64
    let editCount: Int64
    let deleted: Bool
    let markdown: String
}
struct ReplicaInspection {
    let container: ObjId
    let records: [UUID: ReplicaRecord]
    let snapshot: ReplicaSnapshot
    func nextPriority() throws -> UInt64 {
        let largest = records.values.map(\.priority).max() ?? 0
        guard largest < UInt64.max else { throw ReplicaError.limitExceeded }
        return largest + 1
    }
}
extension PageReplica {
    static func inspect(_ document: Document, identity: ReplicaIdentity, limits: ReplicaLimits) throws -> ReplicaInspection {
        guard case .utf16 = document.textEncoding else { throw ReplicaError.invalidSchema }
        guard Set(document.keys(obj: .ROOT)) == Set(["schemaVersion", "libraryID", "spaceID", "pageID", "blocks"]) else { throw ReplicaError.invalidSchema }
        try exactly(document, object: .ROOT, key: "schemaVersion", value: .Scalar(.Uint(1)), error: .invalidSchema)
        for (key, id) in [("libraryID", identity.libraryID), ("spaceID", identity.spaceID), ("pageID", identity.pageID)] { try exactly(document, object: .ROOT, key: key, value: .Scalar(.String(id.uuidString)), error: .identityMismatch) }
        let container = try uniqueObject(document, object: .ROOT, key: "blocks", type: .Map)
        let keys = document.keys(obj: container).sorted()
        guard keys.count <= limits.maximumBlocks else { throw ReplicaError.limitExceeded }
        var records: [UUID: ReplicaRecord] = [:], conflicts: [ReplicaConflict] = []
        var totalText = 0
        for key in keys {
            guard let id = UUID(uuidString: key), id.uuidString == key else { throw ReplicaError.invalidSchema }
            let record = try uniqueObject(document, object: container, key: key, type: .Map)
            guard Set(document.keys(obj: record)) == Set(["id", "text", "editCount", "deleted", "deletedAtEditCount", "after", "priority"]) else { throw ReplicaError.invalidSchema }
            try exactly(document, object: record, key: "id", value: .Scalar(.String(key)), error: .invalidSchema)
            let text = try uniqueObject(document, object: record, key: "text", type: .Text)
            let markdown = try document.text(obj: text)
            guard markdown.utf8.count <= limits.maximumTextBytes - totalText else { throw ReplicaError.limitExceeded }
            totalText += markdown.utf8.count
            guard document.length(obj: text) == UInt64(markdown.utf16.count) else { throw ReplicaError.invalidSchema }
            let editValues = try document.getAll(obj: record, key: "editCount")
            guard editValues.count == 1, case .Scalar(.Counter(let editCount))? = editValues.first, editCount >= 0 else { throw ReplicaError.invalidSchema }
            let deletionValues = try document.getAll(obj: record, key: "deleted")
            var deletions: [Bool] = []
            for value in deletionValues { guard case .Scalar(.Boolean(let flag)) = value else { throw ReplicaError.invalidSchema }; deletions.append(flag) }
            guard !deletions.isEmpty else { throw ReplicaError.invalidSchema }
            let deleted = deletions.contains(true)
            if deletionValues.count > 1 { conflicts.append(.deletionState(blockID: id)) }
            let deletionCounts = try document.getAll(obj: record, key: "deletedAtEditCount")
            var captured: [Int64] = []
            for value in deletionCounts { guard case .Scalar(.Int(let number)) = value, number >= 0, number <= editCount else { throw ReplicaError.invalidSchema }; captured.append(number) }
            guard !captured.isEmpty else { throw ReplicaError.invalidSchema }
            if deleted, captured.contains(where: { $0 < editCount }) { conflicts.append(.deletionEdit(blockID: id, recoverableMarkdown: markdown)) }
            let anchorValues = try document.getAll(obj: record, key: "after")
            var anchors: [String] = []
            for value in anchorValues {
                guard case .Scalar(.String(let string)) = value, string.isEmpty || (UUID(uuidString: string)?.uuidString == string && string != key) else { throw ReplicaError.invalidSchema }
                anchors.append(string)
            }
            guard !anchors.isEmpty, case .Scalar(.String(let selected))? = try document.get(obj: record, key: "after") else { throw ReplicaError.invalidSchema }
            if anchors.count > 1 { conflicts.append(.ordering(blockID: id, anchors: anchors.sorted())) }
            let priorities = try document.getAll(obj: record, key: "priority")
            var priority: UInt64 = 0
            guard !priorities.isEmpty else { throw ReplicaError.invalidSchema }
            for value in priorities { guard case .Scalar(.Uint(let number)) = value else { throw ReplicaError.invalidSchema }; priority = max(priority, number) }
            records[id] = ReplicaRecord(id: id, object: record, text: text, anchor: selected.isEmpty ? nil : UUID(uuidString: selected), priority: priority, editCount: editCount, deleted: deleted, markdown: markdown)
        }
        for record in records.values { if let anchor = record.anchor, records[anchor] == nil { throw ReplicaError.invalidSchema } }
        let ordering = normalizedOrder(records)
        conflicts += ordering.conflicts
        let blocks = ordering.ids.map { id in let r = records[id]!; return ReplicaBlock(id: id, markdown: r.markdown, isDeleted: r.deleted) }
        return ReplicaInspection(container: container, records: records, snapshot: ReplicaSnapshot(identity: identity, blocks: blocks, conflicts: conflicts, version: ReplicaVersion(heads: document.heads().raw())))
    }
    static func exactly(_ document: Document, object: ObjId, key: String, value: Value, error: ReplicaError) throws {
        guard try document.getAll(obj: object, key: key) == [value] else { throw error }
    }
    static func uniqueObject(_ document: Document, object: ObjId, key: String, type: ObjType) throws -> ObjId {
        let values = try document.getAll(obj: object, key: key)
        guard values.count == 1, case .Object(let id, let actual)? = values.first, actual == type else { throw ReplicaError.invalidSchema }
        return id
    }
    static func normalizedOrder(_ records: [UUID: ReplicaRecord]) -> (ids: [UUID], conflicts: [ReplicaConflict]) {
        let sorted = records.keys.sorted { $0.uuidString < $1.uuidString }
        var covered: Set<UUID> = [], virtualRoots: Set<UUID> = [], conflicts: [ReplicaConflict] = []
        // Find predecessor cycles without recursion, break each deterministically
        // in the value snapshot only. The underlying conflict remains observable.
        for start in sorted where !covered.contains(start) {
            var path: [UUID] = [], positions: [UUID: Int] = [:], next: UUID? = start
            while let id = next, !covered.contains(id) {
                if let index = positions[id] {
                    let cycle = Array(path[index...]).sorted { $0.uuidString < $1.uuidString }
                    virtualRoots.insert(cycle[0]); conflicts.append(.orderingCycle(cycle)); break
                }
                positions[id] = path.count; path.append(id); next = records[id]?.anchor
            }
            covered.formUnion(path)
        }
        var children: [UUID?: [UUID]] = [:]
        for record in records.values { children[virtualRoots.contains(record.id) ? nil : record.anchor, default: []].append(record.id) }
        for anchor in Array(children.keys) {
            children[anchor]!.sort { a, b in let left = records[a]!, right = records[b]!; return left.priority == right.priority ? a.uuidString < b.uuidString : left.priority > right.priority }
            let grouped = Dictionary(grouping: children[anchor]!, by: { records[$0]!.priority })
            for priority in grouped.keys.sorted() {
                let peers = grouped[priority]!.sorted { $0.uuidString < $1.uuidString }
                if peers.count > 1 { conflicts.append(.concurrentPlacement(anchor: anchor, blocks: peers)) }
            }
        }
        // Sort the group-derived conflicts independently of dictionary iteration.
        conflicts.sort { conflictKey($0) < conflictKey($1) }
        var stack = Array((children[nil] ?? []).reversed()), visited: Set<UUID> = [], ids: [UUID] = []
        while let id = stack.popLast() { guard visited.insert(id).inserted else { continue }; ids.append(id); stack.append(contentsOf: (children[id] ?? []).reversed()) }
        ids.append(contentsOf: sorted.filter { !visited.contains($0) })
        return (ids, conflicts)
    }
    static func conflictKey(_ conflict: ReplicaConflict) -> String {
        switch conflict {
        case .orderingCycle(let ids): "cycle:" + ids.map(\.uuidString).joined(separator: ",")
        case .concurrentPlacement(let anchor, let ids): "placement:" + (anchor?.uuidString ?? "") + ids.map(\.uuidString).joined(separator: ",")
        default: String(describing: conflict)
        }
    }
}
