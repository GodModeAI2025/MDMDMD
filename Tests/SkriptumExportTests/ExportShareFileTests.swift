import Foundation
import Testing
@testable import SkriptumExport

private final class FileCheckpoint: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let failureAt: Int
    let cancellation: Bool
    init(failureAt: Int, cancellation: Bool = true) { self.failureAt = failureAt; self.cancellation = cancellation }
    func check() throws {
        lock.lock(); count += 1; let shouldFail = count == failureAt; lock.unlock()
        if shouldFail {
            if cancellation { throw CancellationError() }
            throw CocoaError(.fileWriteOutOfSpace)
        }
    }
}

private func exportTestRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Scriptum-ShareFile-Test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    return root
}

private final class ParentCancellationSlot: @unchecked Sendable {
    private let condition = NSCondition()
    private var task: Task<URL, Error>?
    private var calls = 0
    func install(_ task: Task<URL, Error>) {
        condition.lock(); self.task = task; condition.broadcast(); condition.unlock()
    }
    func checkpoint() {
        condition.lock(); calls += 1
        guard calls == 3 else { condition.unlock(); return }
        while task == nil { condition.wait() }
        let parent = task
        condition.unlock()
        parent?.cancel()
    }
}

@Test func shareFileActualParentCancellationDuringWriteRejectsURLAndCleansDisk() async throws {
    let root = try exportTestRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("owned")
    let slot = ParentCancellationSlot()
    let task = Task {
        try await ExportShareFile.write(Data(repeating: 13, count: 2_097_152), suggestedName: "Book", fileExtension: "pdf",
            directory: directory, checkpoint: { slot.checkpoint() })
    }
    slot.install(task)
    do { _ = try await task.value; Issue.record("Parent cancellation admitted a share URL") }
    catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
    #expect(!FileManager.default.fileExists(atPath: directory.path))
}

@Test func shareFilePublishesExactSlicedBinaryAndSanitizedUnicodeName() async throws {
    let root = try exportTestRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let original = Data((0..<800_000).map { UInt8($0 % 251) })
    let slice = original[17..<799_985]
    let directory = root.appendingPathComponent("owned")
    let url = try await ExportShareFile.write(slice, suggestedName: "Kapitel 🦊/../\nEnde", fileExtension: "zip", directory: directory)
    #expect(url.deletingLastPathComponent().path == directory.path)
    #expect(url.lastPathComponent == "Kapitel 🦊-..--Ende.zip")
    #expect(try Data(contentsOf: url) == slice)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [url.lastPathComponent])
}

@Test(arguments: [1, 3, 7])
func shareFileCancellationRemovesOwnedDirectoryBeforeDuringAndAfterPublication(point: Int) async throws {
    let root = try exportTestRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("owned")
    let checkpoint = FileCheckpoint(failureAt: point)
    do {
        _ = try await ExportShareFile.write(Data(repeating: 42, count: 1_048_576), suggestedName: "Book", fileExtension: "pdf",
            directory: directory, checkpoint: { try checkpoint.check() })
        Issue.record("Canceled share file published a URL")
    } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
    #expect(!FileManager.default.fileExists(atPath: directory.path))
}

@Test func shareFileWriteFailurePreservesOtherExportsAndExistingDirectory() async throws {
    let root = try exportTestRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let borrowed = root.appendingPathComponent("existing")
    try FileManager.default.createDirectory(at: borrowed, withIntermediateDirectories: false)
    let sentinel = borrowed.appendingPathComponent("keep.txt")
    try Data("Original 🦊".utf8).write(to: sentinel)
    do {
        _ = try await ExportShareFile.write(Data([1]), suggestedName: "Book", fileExtension: "pdf", directory: borrowed)
        Issue.record("An existing directory was claimed")
    } catch {}
    #expect(try Data(contentsOf: sentinel) == Data("Original 🦊".utf8))
    let directory = root.appendingPathComponent("owned")
    let checkpoint = FileCheckpoint(failureAt: 3, cancellation: false)
    do {
        _ = try await ExportShareFile.write(Data(repeating: 7, count: 600_000), suggestedName: "Book", fileExtension: "pdf",
            directory: directory, checkpoint: { try checkpoint.check() })
        Issue.record("Failed write published a URL")
    } catch let error as CocoaError { #expect(error.code == .fileWriteOutOfSpace) }
    #expect(!FileManager.default.fileExists(atPath: directory.path))
    #expect(try Data(contentsOf: sentinel) == Data("Original 🦊".utf8))
    let next = try await ExportShareFile.write(Data(), suggestedName: " ", fileExtension: "md", directory: directory)
    #expect(next.lastPathComponent == "Scriptum.md")
    #expect(try Data(contentsOf: next).isEmpty)
}

@Test func shareFileRejectsUnsafeExtensionWithoutCreatingFiles() async throws {
    let root = try exportTestRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("owned")
    do {
        _ = try await ExportShareFile.write(Data([1]), suggestedName: "Book", fileExtension: "../pdf", directory: directory)
        Issue.record("Unsafe extension accepted")
    } catch ExportError.invalidMetadata {} catch { Issue.record("Unexpected error: \(error)") }
    #expect(!FileManager.default.fileExists(atPath: directory.path))
}
