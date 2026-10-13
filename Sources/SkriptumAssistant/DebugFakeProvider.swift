#if DEBUG
import Foundation

/// Nur für Debug-Builds mit der Umgebungsvariable SCRIPTUM_FAKE_AI: lokaler Anbieter ohne Netzwerk für die Oberflächenprüfung.
struct DebugFakeProvider: AIProvider {
    let id: AIProviderID
    let capabilities = AICapabilities(textStreaming: true, requiresCredential: false)
    static var enabled: Bool { ProcessInfo.processInfo.environment["SCRIPTUM_FAKE_AI"] != nil }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        let task = request.prompt.components(separatedBy: "Auftrag:\n").last ?? ""
        let strict = request.instructions.contains("vollständigen neuen Markdown-Text dieses Zielbereichs")
        let reply: String
        if strict { reply = "Äpfel schälen,\nTeig bereiten,\nApfelkuchen backen." }
        else if task.lowercased().contains("gedicht") || task.lowercased().contains("kürzer") {
            reply = "Gern.\n\(AssistantReply.begin)\nApfelkuchen\n\nGoldener Teig, warmer Duft.\n\(AssistantReply.end)\nDer Text ist ersetzt."
        } else { reply = "Das ist eine Antwort im Chat." }
        return AsyncThrowingStream { continuation in
            continuation.yield(.textDelta(reply)); continuation.yield(.completed); continuation.finish()
        }
    }
}
#endif
