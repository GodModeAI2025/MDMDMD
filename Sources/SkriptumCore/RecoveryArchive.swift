import Foundation

public struct RecoveryRecord<Value: Codable & Equatable & Sendable>: Codable, Identifiable, Sendable {
    public let id: UUID
    public let value: Value
    public let capturedAt: Date
    public init(id: UUID = UUID(), value: Value, capturedAt: Date = Date()) {
        self.id = id; self.value = value; self.capturedAt = capturedAt
    }
}

/// Every distinct draft receives an independent file. Equal repeat captures reuse
/// the existing record; the caller controls byte-sensitive payload equality.
public final class RecoveryArchive<Value: Codable & Equatable & Sendable> {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func records() throws -> [RecoveryRecord<Value>] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        return try urls.map { try JSONDecoder().decode(RecoveryRecord<Value>.self, from: Data(contentsOf: $0)) }.sorted { $0.capturedAt > $1.capturedAt }
    }
    @discardableResult public func preserve(_ value: Value) throws -> RecoveryRecord<Value> {
        if let existing = try records().first(where: { $0.value == value }) { return existing }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let record = RecoveryRecord(value: value)
        try JSONEncoder().encode(record).write(to: directory.appendingPathComponent(record.id.uuidString + ".json"), options: .atomic)
        return record
    }
    public func remove(_ id: UUID) throws {
        try FileManager.default.removeItem(at: directory.appendingPathComponent(id.uuidString + ".json"))
    }
}
