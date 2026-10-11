import Foundation

public enum RecoveryCompleteness: String, Codable, Sendable { case sourceOnly, complete }
public enum RecoveryArchiveError: Error, Equatable { case invalidRecord, unsafePath, verificationFailed }
public struct RecoveryReadIssue: Sendable {
    public let fileName: String
    public let message: String
}
public struct RecoveryRecord<Value: Codable & Equatable & Sendable>: Codable, Identifiable, Sendable {
    public let id: UUID
    public let value: Value
    public let capturedAt: Date
    /// Missing in legacy records, which were published only after media checks.
    public let completeness: RecoveryCompleteness?
    public var isComplete: Bool { completeness != .sourceOnly }
    public init(id: UUID = UUID(), value: Value, capturedAt: Date = Date(), completeness: RecoveryCompleteness = .complete) {
        self.id = id; self.value = value; self.capturedAt = capturedAt; self.completeness = completeness
    }
}

/// Values are immutable per record ID. Completeness may advance only after the
/// caller verifies its dependent resources; incomplete source remains readable.
public final class RecoveryArchive<Value: Codable & Equatable & Sendable> {
    public struct Scan {
        public let records: [RecoveryRecord<Value>]
        public let issues: [RecoveryReadIssue]
    }
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    private func validateDirectory(create: Bool = false) throws -> Bool {
        if create { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        guard FileManager.default.fileExists(atPath: directory.path) else { return false }
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw RecoveryArchiveError.unsafePath }
        return true
    }
    private func read(_ url: URL) throws -> RecoveryRecord<Value> {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw RecoveryArchiveError.unsafePath }
        let record = try JSONDecoder().decode(RecoveryRecord<Value>.self, from: Data(contentsOf: url))
        guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) == record.id else {
            throw RecoveryArchiveError.invalidRecord
        }
        return record
    }
    private func path(_ id: UUID) throws -> URL {
        _ = try validateDirectory()
        let canonical = directory.appendingPathComponent(id.uuidString + ".json")
        if FileManager.default.fileExists(atPath: canonical.path) { return canonical }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return files.first { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) == id } ?? canonical
    }
    public func scanRecords() throws -> Scan {
        guard try validateDirectory() else { return Scan(records: [], issues: []) }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        var records: [RecoveryRecord<Value>] = [], issues: [RecoveryReadIssue] = []
        for url in urls {
            do { records.append(try read(url)) }
            catch { issues.append(RecoveryReadIssue(fileName: url.lastPathComponent, message: error.localizedDescription)) }
        }
        return Scan(records: records.sorted { $0.capturedAt > $1.capturedAt }, issues: issues)
    }
    /// Strict readers retain the old all-records-readable contract.
    public func records() throws -> [RecoveryRecord<Value>] {
        let scan = try scanRecords()
        guard scan.issues.isEmpty else { throw RecoveryArchiveError.invalidRecord }
        return scan.records
    }
    private func write(_ record: RecoveryRecord<Value>, at url: URL) throws -> RecoveryRecord<Value> {
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
        let stored = try read(url)
        guard stored.id == record.id, stored.value == record.value, stored.capturedAt == record.capturedAt,
              stored.completeness == record.completeness else { throw RecoveryArchiveError.verificationFailed }
        return stored
    }
    /// Corrupt unrelated files stay untouched and cannot prevent a new capture.
    @discardableResult public func preserve(_ value: Value, completeness: RecoveryCompleteness = .complete) throws -> RecoveryRecord<Value> {
        _ = try validateDirectory(create: true)
        if let existing = try scanRecords().records.first(where: { $0.value == value }) {
            if (existing.completeness ?? .complete) == completeness { return existing }
            return try setCompleteness(existing.id, to: completeness, expectedValue: value)
        }
        let record = RecoveryRecord(value: value, completeness: completeness)
        return try write(record, at: directory.appendingPathComponent(record.id.uuidString + ".json"))
    }
    @discardableResult public func setCompleteness(_ id: UUID, to completeness: RecoveryCompleteness, expectedValue: Value) throws -> RecoveryRecord<Value> {
        let url = try path(id), existing = try read(url)
        guard existing.value == expectedValue else { throw RecoveryArchiveError.verificationFailed }
        let record = RecoveryRecord(id: existing.id, value: existing.value, capturedAt: existing.capturedAt, completeness: completeness)
        return try write(record, at: url)
    }
    public func remove(_ id: UUID, expectedValue: Value? = nil) throws {
        let url = try path(id), existing = try read(url)
        if let expectedValue, existing.value != expectedValue { throw RecoveryArchiveError.verificationFailed }
        try FileManager.default.removeItem(at: url)
    }
}
