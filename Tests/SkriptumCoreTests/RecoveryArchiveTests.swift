import Foundation
import Testing
@testable import SkriptumCore

private struct ByteDraft: Codable, Equatable, Sendable {
    let baseline: UUID
    let title: Data
    let text: Data
    let favorite: Bool
}

@Test func distinctStaleDraftsNeverOverwriteAndRepeatsDeduplicate() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let archive = RecoveryArchive<ByteDraft>(directory: directory)
    let baseline = UUID()
    let first = ByteDraft(baseline: baseline, title: Data("Titel".utf8), text: Data("Erster Entwurf".utf8), favorite: false)
    let second = ByteDraft(baseline: baseline, title: first.title, text: Data("Zweiter Entwurf".utf8), favorite: false)
    let a = try archive.preserve(first)
    let b = try archive.preserve(second)
    let repeated = try archive.preserve(first)
    #expect(a.id != b.id)
    #expect(a.id == repeated.id)
    let reopened = RecoveryArchive<ByteDraft>(directory: directory)
    #expect(try reopened.records().count == 2)
    #expect(try reopened.records().contains(where: { $0.value == first }))
    #expect(try reopened.records().contains(where: { $0.value == second }))
}

@Test func metadataAndUnicodeByteDifferencesHaveIndependentRecoveries() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let archive = RecoveryArchive<ByteDraft>(directory: directory)
    let baseline = UUID()
    let composed = ByteDraft(baseline: baseline, title: Data("Café".utf8), text: Data("Text".utf8), favorite: false)
    let decomposed = ByteDraft(baseline: baseline, title: Data("Cafe\u{301}".utf8), text: composed.text, favorite: false)
    let metadata = ByteDraft(baseline: baseline, title: composed.title, text: composed.text, favorite: true)
    let a = try archive.preserve(composed)
    let b = try archive.preserve(decomposed)
    let c = try archive.preserve(metadata)
    #expect(Set([a.id, b.id, c.id]).count == 3)
    #expect(try archive.records().count == 3)
    try archive.remove(b.id)
    #expect(try archive.records().count == 2)
    #expect(try archive.records().contains(where: { $0.id == a.id }))
    #expect(try archive.records().contains(where: { $0.id == c.id }))
}

@Test func recoveryScanKeepsHealthyRecordsAndNeverOverwritesCorruptNeighbors() throws {
    let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let archive = RecoveryArchive<String>(directory: root)
    _ = try archive.preserve("First")
    let bad = root.appending(path: UUID().uuidString + ".json")
    let bytes = Data("not valid JSON".utf8); try bytes.write(to: bad)
    let second = try archive.preserve("Second", completeness: .sourceOnly)
    let scan = try archive.scanRecords()
    #expect(scan.records.count == 2 && scan.issues.count == 1)
    #expect(!second.isComplete)
    #expect(try Data(contentsOf: bad) == bytes)
    #expect(throws: RecoveryArchiveError.invalidRecord) { try archive.records() }
    let completed = try archive.setCompleteness(second.id, to: .complete, expectedValue: "Second")
    #expect(completed.id == second.id && completed.capturedAt == second.capturedAt && completed.isComplete)
    #expect(throws: RecoveryArchiveError.verificationFailed) { try archive.remove(second.id, expectedValue: "Different source") }
    #expect(try archive.scanRecords().records.count == 2)
}

@Test func legacyRecoveryRecordRemainsCompleteAndMismatchedFileIdentityIsSkipped() throws {
    let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let record = RecoveryRecord(value: "Legacy")
    var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
    payload.removeValue(forKey: "completeness")
    let data = try JSONSerialization.data(withJSONObject: payload)
    try data.write(to: root.appending(path: record.id.uuidString + ".json"))
    try data.write(to: root.appending(path: UUID().uuidString + ".json"))
    let scan = try RecoveryArchive<String>(directory: root).scanRecords()
    #expect(scan.records.count == 1 && scan.issues.count == 1)
    #expect(scan.records.first?.isComplete == true)
}
