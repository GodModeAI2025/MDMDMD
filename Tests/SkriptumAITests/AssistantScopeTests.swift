import Foundation
import Testing
@testable import SkriptumAI

private struct MockProvider: AIProvider {
    let id: AIProviderID
    let output: AsyncThrowingStream<AIEvent, Error>
    let capture: @Sendable (AIRequest) -> Void
    var capabilities: AICapabilities { .init(textStreaming: true, requiresCredential: false) }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> { capture(request); return output }
}
private final class Captured: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AIRequest?
    func set(_ request: AIRequest) { lock.lock(); defer { lock.unlock() }; stored = request }
    func get() -> AIRequest? { lock.lock(); defer { lock.unlock() }; return stored }
}

private let scopedPage = "# Titel\n\nErster Absatz über EnBW.\n\n## Abschnitt\n\n![](media/welcome.png)\n\nZweiter Absatz mit Text.\n\n## Ende\n\nSchluss."

@MainActor @Test func chatContextIsScopedAndMediaLinksNeverReachTheProvider() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let assistant = PageAssistant(pageID: UUID(), directory: directory)
    let nsPage = scopedPage as NSString
    #expect(AssistantScope.blockRanges(in: scopedPage).count == 7)
    let second = try #require(AssistantScope.blockRange(in: scopedPage, containing: nsPage.range(of: "Zweiter").location + 3))
    #expect(nsPage.substring(with: second) == "Zweiter Absatz mit Text.")
    let scope = AssistantScope.resolve(markdown: scopedPage, selection: nil, activeBlock: second)
    let context = AssistantScope.chatContext(markdown: scopedPage, scope: scope)
    #expect(context == "## Abschnitt\n\nZweiter Absatz mit Text.\n\n## Ende")
    #expect(!context.contains("Erster Absatz") && !context.contains("Schluss"))
    let output = AsyncThrowingStream<AIEvent, Error>.makeStream(), capture = Captured()
    let raw = scopedPage + "\n![Foto](media/x y.jpg)"
    let submission = try assistant.prepare(providerID: .openAIKey, model: "m", prompt: "Was ist EnBW?", context: raw, revisionMode: false,
                                           references: [.init(title: "R", markdown: "Ref ![](media/ref.png) Ende")])
    #expect(assistant.run(provider: MockProvider(id: .openAIKey, output: output.stream, capture: { capture.set($0) }), submission: submission, consentID: submission.id))
    for _ in 0..<50 where capture.get() == nil { await Task.yield() }
    let request = try #require(capture.get())
    #expect(!request.prompt.contains("media") && !request.prompt.contains("x y.jpg") && !request.prompt.contains("!["))
    #expect(request.prompt.contains("Zweiter Absatz") && request.prompt.contains("Ref  Ende"))
    #expect(request.instructions.contains("Wiederhole niemals den Text des Dokuments"))
    #expect(submission.contextCharacters == AssistantMedia.stripLinks(raw).count)
    output.continuation.yield(.completed); output.continuation.finish()
    if let task = assistant.task { await task.value }
}

@MainActor @Test func revisionTargetKeepsImageLinksSoApplyingCannotDeleteThem() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let submission = try PageAssistant(pageID: UUID(), directory: directory).prepare(providerID: .openAIKey, model: "m", prompt: "Kürze", context: "A ![](media/a.png) B", revisionMode: true)
    #expect(submission.request.prompt.contains("a.png"))
    #expect(!submission.request.instructions.contains("Wiederhole niemals"))
}

@Test func selectionBeatsActiveBlockBeatsPage() {
    let text = "Eins\n\nZwei"
    let selection = NSRange(location: 0, length: 2), block = NSRange(location: 6, length: 4)
    #expect(AssistantScope.resolve(markdown: text, selection: selection, activeBlock: block) == .init(kind: .selection, range: selection))
    #expect(AssistantScope.resolve(markdown: text, selection: NSRange(location: 3, length: 0), activeBlock: block) == .init(kind: .block, range: block))
    #expect(AssistantScope.resolve(markdown: text, selection: nil, activeBlock: nil) == .page)
    #expect(AssistantScope.resolve(markdown: text, selection: NSRange(location: 4, length: 99), activeBlock: NSRange(location: -1, length: 2)) == .page)
    #expect(AssistantScope.chatContext(markdown: text, scope: .init(kind: .selection, range: selection)) == "Ei")
    #expect(AssistantScope.chatContext(markdown: text, scope: .page) == text)
}

@Test(arguments: [
    ("Ergänze Recherche was EnBW ist", AssistantIntent.edit), ("Bitte kürze den Absatz", .edit), ("schreibe einen Schluss", .edit),
    ("Füge eine Quelle hinzu", .edit), ("Überarbeite den Ton.", .edit), ("ueberarbeite das", .edit), ("Ändere die Überschrift", .edit),
    ("Was ist EnBW?", .chat), ("Kannst du das kürzen?", .chat), ("Fasse zusammen", .chat), ("Erkläre mir den Absatz", .chat), ("", .chat)
]) func editVerbsRouteToProposalFlow(prompt: String, intent: AssistantIntent) {
    #expect(AssistantIntent.classify(prompt) == intent)
}
