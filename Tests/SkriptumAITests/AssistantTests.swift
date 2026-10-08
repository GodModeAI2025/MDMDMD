import Foundation
import Testing
@testable import SkriptumAI

private struct ControlledProvider: AIProvider {
    let id: AIProviderID
    let output: AsyncThrowingStream<AIEvent, Error>
    let capture: @Sendable (AIRequest) -> Void
    var capabilities: AICapabilities { .init(textStreaming: true, requiresCredential: false) }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> { capture(request); return output }
}
private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AIRequest?
    func set(_ request: AIRequest) { lock.lock(); defer { lock.unlock() }; stored = request }
    func get() -> AIRequest? { lock.lock(); defer { lock.unlock() }; return stored }
}
@MainActor @Test func stoppedRequestCannotFinalizeReplacement() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let assistant = PageAssistant(pageID: UUID(), directory: directory)
    let old = AsyncThrowingStream<AIEvent, Error>.makeStream()
    let fresh = AsyncThrowingStream<AIEvent, Error>.makeStream()
    assistant.run(provider: ControlledProvider(id: .openAIKey, output: old.stream, capture: { _ in }), model: "test", prompt: "old", context: "", revisionMode: false)
    await Task.yield()
    assistant.stop()
    assistant.run(provider: ControlledProvider(id: .openAIKey, output: fresh.stream, capture: { _ in }), model: "test", prompt: "fresh", context: "", revisionMode: false)
    old.continuation.finish(throwing: CancellationError())
    for _ in 0..<20 { await Task.yield() }
    #expect(assistant.running)
    #expect(assistant.error == nil)
    fresh.continuation.yield(.textDelta("New answer")); fresh.continuation.yield(.completed); fresh.continuation.finish()
    let task = try #require(assistant.task)
    await task.value
    #expect(assistant.response == "New answer")
    #expect(assistant.completed)
    #expect(!assistant.running)
}
@MainActor @Test func historyStaysWithinSelectedProviderAndCorruptChatIsPreserved() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let assistant = PageAssistant(pageID: UUID(), directory: directory)
    assistant.entries = [.init(role: "assistant", text: "PRIVATE OPENAI HISTORY", provider: AIProviderID.openAIKey.rawValue)]
    let output = AsyncThrowingStream<AIEvent, Error>.makeStream(); let capture = RequestCapture()
    assistant.run(provider: ControlledProvider(id: .anthropicKey, output: output.stream, capture: { capture.set($0) }), model: "test", prompt: "help", context: "selected", revisionMode: false)
    for _ in 0..<50 where capture.get() == nil { await Task.yield() }
    let request = try #require(capture.get())
    #expect(!request.prompt.contains("PRIVATE OPENAI HISTORY"))
    output.continuation.yield(.completed); output.continuation.finish()
    if let task = assistant.task { await task.value }
    let pageID = UUID(); let file = directory.appending(path: "\(pageID.uuidString).json")
    try Data("broken source".utf8).write(to: file)
    let broken = PageAssistant(pageID: pageID, directory: directory)
    broken.run(provider: ControlledProvider(id: .anthropicKey, output: output.stream, capture: { _ in }), model: "test", prompt: "new", context: "", revisionMode: false)
    #expect(!broken.running)
    #expect(try String(contentsOf: file, encoding: .utf8) == "broken source")
}
