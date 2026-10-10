import Foundation
import Testing
@testable import SkriptumExport

private actor ExportCancellationGate {
    private var entered = false
    private(set) var workerCancelled = false
    func recordCancellation(_ value: Bool) { workerCancelled = value }
    private var observer: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    func park() async {
        entered = true
        observer?.resume(); observer = nil
        await withCheckedContinuation { release = $0 }
    }
    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { observer = $0 }
    }
    func finish() { release?.resume(); release = nil }
}

@Test func cancelledExportRejectsAnUncooperativeLateResult() async throws {
    let gate = ExportCancellationGate()
    let task = Task {
        try await ExportWorker.run {
            await gate.park() // Deliberately ignores cancellation until released.
            return "late archive"
        }
    }
    await gate.waitForEntry()
    task.cancel()
    await gate.finish()
    do { _ = try await task.value; Issue.record("Cancelled export admitted a late archive") }
    catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
    // A later independent export must not inherit a previous cancellation.
    let next = try await ExportWorker.run { "new archive" }
    #expect(next == "new archive")
}

@Test func exportWorkerForwardsCancellationToSuspendedOperation() async {
    let gate = ExportCancellationGate()
    let task = Task {
        try await ExportWorker.run {
            await gate.park()
            await gate.recordCancellation(Task.isCancelled)
            try await Task.sleep(for: .seconds(60))
            return 1
        }
    }
    await gate.waitForEntry(); task.cancel(); await gate.finish()
    do { _ = try await task.value; Issue.record("Worker did not observe parent cancellation") }
    catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
    #expect(await gate.workerCancelled)
}

@Test func cancelledTaskRejectsZIPAndSemanticWorkAtAdmission() async {
    let gate = ExportCancellationGate()
    let task = Task {
        await gate.park()
        do {
            _ = try StoredZIP.archive([.init(name: "large.bin", data: Data(repeating: 42, count: 1_000_000))])
            Issue.record("Cancelled ZIP succeeded")
        } catch is CancellationError {} catch { Issue.record("Unexpected ZIP error: \(error)") }
        do {
            _ = try ExportEngine.export(ExportInput(title: "Book", markdown: "# Chapter"), format: .html)
            Issue.record("Cancelled semantic export succeeded")
        } catch is CancellationError {} catch { Issue.record("Unexpected parser error: \(error)") }
    }
    await gate.waitForEntry(); task.cancel(); await gate.finish(); await task.value
}
