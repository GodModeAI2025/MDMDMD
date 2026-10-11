import Foundation
import CryptoKit
import Testing
@testable import SkriptumCore

@MainActor struct RecoveryEvidenceExporterTests {
    private func fixture() throws -> (URL, LibraryStore) {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let store = try LibraryStore(directory: root.appending(path: "Library"))
        let space = try store.createSpace(title: "Book")
        _ = try store.createPage(spaceID: space.id, title: "Chapter", markdown: "e\u{301} 🦊\r\n")
        return (root, store)
    }
    @Test func opaqueCorruptOriginalsArePreservedAndChecksummedWithoutRepair() async throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let edits = store.directory.appending(path: "edits"); try FileManager.default.createDirectory(at: edits, withIntermediateDirectories: true)
        let broken = edits.appending(path: "broken.json"), data = Data([0, 255, 1, 2])
        try data.write(to: broken)
        let json = try Data(contentsOf: store.directory.appending(path: "library.json"))
        let destination = root.appending(path: "Rescue.zip")
        let receipt = try await RecoveryEvidenceExporter.archive(from: store.directory, to: destination)
        let item = try #require(receipt.files.first(where: { $0.path == "edits/broken.json" }))
        #expect(item.bytes == 4 && item.sha256 == SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        #expect(receipt.files.contains(where: { $0.path == "library.json" }))
        #expect(receipt.excludedPaths == [".library.lock"])
        #expect(try Data(contentsOf: broken) == data)
        #expect(try Data(contentsOf: store.directory.appending(path: "library.json")) == json)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        let body = try Data(contentsOf: destination)
        #expect(body.prefix(4) == Data([0x50, 0x4b, 3, 4]))
        #expect(body.suffix(22).prefix(4) == Data([0x50, 0x4b, 5, 6]))
    }
    @Test func symlinksAndExistingDestinationsFailWithoutPartialPublication() async throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "Rescue.zip"), prior = Data("Existing export".utf8)
        try prior.write(to: destination)
        do { _ = try await RecoveryEvidenceExporter.archive(from: store.directory, to: destination); Issue.record("Overwrote existing destination") }
        catch RecoveryEvidenceError.destinationExists {}
        #expect(try Data(contentsOf: destination) == prior)
        let linked = store.directory.appending(path: "external-link")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: destination)
        let fresh = root.appending(path: "Fresh.zip")
        do { _ = try await RecoveryEvidenceExporter.archive(from: store.directory, to: fresh); Issue.record("Followed symlink") }
        catch RecoveryEvidenceError.unsafeEntry {}
        #expect(!FileManager.default.fileExists(atPath: fresh.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".scriptum-rescue-") })
        #expect(try Data(contentsOf: destination) == prior)
    }
    @Test func canceledRequestsNeverCreateOutputAndInsideLibraryDestinationsAreRejected() async throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "Canceled.zip")
        let task = Task { try await RecoveryEvidenceExporter.archive(from: store.directory, to: destination) }
        task.cancel()
        do { _ = try await task.value; Issue.record("Ignored cancellation") } catch is CancellationError {}
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let inside = store.directory.appending(path: "Recursive.zip")
        do { _ = try await RecoveryEvidenceExporter.archive(from: store.directory, to: inside); Issue.record("Archived recursively") }
        catch RecoveryEvidenceError.unsafeEntry {}
        #expect(!FileManager.default.fileExists(atPath: inside.path))
    }
}

extension RecoveryEvidenceExporterTests {
    @Test func oversizedOriginalFailsWithoutPublishingOrChangingSparseFile() async throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let large = store.directory.appending(path: "oversized-original")
        #expect(FileManager.default.createFile(atPath: large.path, contents: nil))
        let file = try FileHandle(forWritingTo: large)
        try file.truncate(atOffset: 513 * 1024 * 1024); try file.close()
        let destination = root.appending(path: "TooLarge.zip")
        do { _ = try await RecoveryEvidenceExporter.archive(from: store.directory, to: destination); Issue.record("Ignored file bound") }
        catch RecoveryEvidenceError.bounds {}
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect((try FileManager.default.attributesOfItem(atPath: large.path)[.size] as? NSNumber)?.int64Value == 513 * 1024 * 1024)
    }
}
