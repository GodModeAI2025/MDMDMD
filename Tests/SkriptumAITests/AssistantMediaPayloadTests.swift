import Foundation
import Testing
@testable import SkriptumAI

private struct MediaCaptureProvider: AIProvider {
    let id = AIProviderID.openAIKey
    let captured: @Sendable (AIRequest) -> Void
    var capabilities: AICapabilities { .init(textStreaming: true, requiresCredential: false) }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        captured(request)
        return AsyncThrowingStream { $0.yield(.completed); $0.finish() }
    }
}

private final class MediaRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var request: AIRequest?
    func set(_ value: AIRequest) { lock.lock(); defer { lock.unlock() }; request = value }
    func get() -> AIRequest? { lock.lock(); defer { lock.unlock() }; return request }
}

private func payloadContext(_ request: AIRequest) throws -> (String, String) {
    let json = try #require(request.prompt.components(separatedBy: "Dokumentkontext (JSON-Daten):\n").last?.components(separatedBy: "\n\nAuftrag:").first)
    let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let target = try #require(object["target"] as? String)
    let references = try #require(object["references"] as? [[String: String]])
    return (target, try #require(references.first?["markdown"]))
}

@MainActor @Test(arguments: [
    "![Foto](media/folder(one)/PRIVATE-image.png \"Bildtitel\")",
    #"![Foto](media/PRIVATE-image\)name.png)"#,
    "![Foto [mit Klammern]](media/PRIVATE-image.png)",
    "![Foto][private]\n\n[private]: media/PRIVATE-image.png",
    "![private][]\n\n[private]: <media/PRIVATE image.png> \"Titel\"",
    "![private]\n\n[private]:\n  media/PRIVATE-image.png\n  \"Mehrzeiliger Titel\"",
    "> ![Foto][private]\n>\n> [private]: media/PRIVATE-image.png",
]) func assistantMediaDestinationsStayOutOfReadOnlyProviderPayload(imageMarkdown: String) async throws {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let assistant = PageAssistant(pageID: UUID(), directory: directory)
    let original = "Vorher 🦊\n\n" + imageMarkdown + "\n\nNachher e\u{301}."
    let bytes = Data(original.utf8)
    let submission = try assistant.prepare(providerID: .openAIKey, model: "test", prompt: "Erkläre den Text", context: original,
                                           revisionMode: false, references: [.init(title: "Quelle", markdown: original)], includeHistory: false)
    let capture = MediaRequestCapture()
    #expect(assistant.run(provider: MediaCaptureProvider(captured: capture.set), submission: submission, consentID: submission.id))
    if let task = assistant.task { await task.value }
    let payload = try payloadContext(#require(capture.get()))
    for text in [payload.0, payload.1] {
        #expect(!text.contains("PRIVATE"))
        #expect(!text.contains("!["))
        #expect(text.contains("Vorher 🦊") && text.contains("Nachher e\u{301}."))
    }
    #expect(Data(original.utf8) == bytes)
}

@MainActor @Test(arguments: [false, true])
func editableAssistantTargetsKeepExactImageSourceWhileReferencesAreFiltered(hybrid: Bool) async throws {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let assistant = PageAssistant(pageID: UUID(), directory: directory)
    let original = "Cafe\u{301} 🦊\r\n![Foto][private]\r\n\r\n[private]: <media/PRIVATE (image).png>\r\n"
    let submission = try assistant.prepare(providerID: .openAIKey, model: "test", prompt: "Kürze den Text", context: original,
                                           revisionMode: !hybrid, references: [.init(title: "Quelle", markdown: original)],
                                           includeHistory: false, hybrid: hybrid)
    let capture = MediaRequestCapture()
    #expect(assistant.run(provider: MediaCaptureProvider(captured: capture.set), submission: submission, consentID: submission.id))
    if let task = assistant.task { await task.value }
    let payload = try payloadContext(#require(capture.get()))
    #expect(Data(payload.0.utf8) == Data(original.utf8))
    #expect(!payload.1.contains("PRIVATE"))
    #expect(submission.contextCharacters == original.count)
}

@Test func assistantImageFilteringKeepsUsefulProseLinksAndLiteralExamples() {
    let source = """
    ![Foto][private]

    [Download][private] und [Dokumentation][docs].

    [private]: media/PRIVATE-image.png
    [docs]: https://example.org/docs

    `![Beispiel](literal-inline.png)`

    ```markdown
    ![Beispiel](literal-code.png)
    ```
    """
    let filtered = AssistantMedia.stripLinks(source)
    #expect(!filtered.contains("PRIVATE"))
    #expect(filtered.contains("Download") && filtered.contains("Dokumentation"))
    #expect(filtered.contains("https://example.org/docs"))
    #expect(filtered.contains("![Beispiel](literal-inline.png)"))
    #expect(filtered.contains("![Beispiel](literal-code.png)"))
}

@Test func assistantNoImageReadContextRetainsOriginalSourceBytes() {
    let source = "Cafe\u{301}  🦊\r\n\r\n\r\n[unused]: https://example.org/research\r\n\r\n[Dokumentation](https://example.org/docs)\r\n"
    #expect(Data(AssistantMedia.stripLinks(source).utf8) == Data(source.utf8))
}
