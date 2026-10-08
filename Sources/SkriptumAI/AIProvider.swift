import Foundation

public enum AIProviderID: String, Codable, CaseIterable, Sendable {
    case openAIKey, anthropicKey, applePCC, chatGPTSubscription
}
public struct AICapabilities: Sendable, Equatable {
    public let textStreaming: Bool
    public let requiresCredential: Bool
    public let requiresApproval: Bool
    public init(textStreaming: Bool, requiresCredential: Bool, requiresApproval: Bool = false) {
        self.textStreaming = textStreaming; self.requiresCredential = requiresCredential; self.requiresApproval = requiresApproval
    }
}
public struct AIRequest: Sendable {
    public let model: String
    public let instructions: String
    public let prompt: String
    public let maximumOutputTokens: Int
    public init(model: String = "", instructions: String = "", prompt: String, maximumOutputTokens: Int = 4096) {
        self.model = model; self.instructions = instructions; self.prompt = prompt; self.maximumOutputTokens = maximumOutputTokens
    }
}
public enum AIEvent: Sendable, Equatable { case textDelta(String), completed }
public enum AIError: Error, Sendable, Equatable, LocalizedError {
    case missingCredential, invalidRequest, unconfiguredSubscription, missingPCCEntitlement, unavailable(String), http(Int), malformedStream, incompleteResponse, remoteFailure
    public var errorDescription: String? {
        switch self {
        case .missingCredential: "Bitte einen API-Schlüssel hinterlegen."
        case .invalidRequest: "Modell, Text oder Ausgabelimit ist ungültig."
        case .unconfiguredSubscription: "ChatGPT-Abo: Der genehmigte kommerzielle mobile OAuth-Zugang ist noch nicht konfiguriert."
        case .missingPCCEntitlement: "Private Cloud Compute benötigt das von Apple genehmigte Entitlement."
        case .unavailable(let reason): "Private Cloud Compute ist nicht verfügbar: \(reason)"
        case .http(let status): "Der KI-Anbieter meldet HTTP \(status)."
        case .malformedStream: "Die KI-Antwort ist nicht lesbar."
        case .incompleteResponse: "Die KI-Antwort wurde nicht vollständig abgeschlossen."
        case .remoteFailure: "Der KI-Anbieter hat die Antwort abgebrochen."
        }
    }
}
public protocol AIProvider: Sendable {
    var id: AIProviderID { get }
    var capabilities: AICapabilities { get }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error>
}

/// Transport exposes status before consuming content; production transport never logs credentials or text.
public struct AIHTTPStream: Sendable {
    public let statusCode: Int
    public let lines: AsyncThrowingStream<String, Error>
    public init(statusCode: Int, lines: AsyncThrowingStream<String, Error>) { self.statusCode = statusCode; self.lines = lines }
}
public protocol AITransport: Sendable { func open(_ request: URLRequest) async throws -> AIHTTPStream }

public struct URLSessionAITransport: AITransport {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    public func open(_ request: URLRequest) async throws -> AIHTTPStream {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw AIError.malformedStream }
        let lines = AsyncThrowingStream<String, Error>(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    var totalBytes = 0
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        totalBytes += line.utf8.count
                        guard totalBytes <= 16 * 1024 * 1024 else { throw AIError.malformedStream }
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
        return AIHTTPStream(statusCode: response.statusCode, lines: lines)
    }
}
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

public struct RemoteAIProvider: AIProvider {
    public let id: AIProviderID
    private let credential: String
    private let transport: any AITransport
    public var capabilities: AICapabilities { AICapabilities(textStreaming: id == .openAIKey || id == .anthropicKey, requiresCredential: true, requiresApproval: id == .chatGPTSubscription) }
    public init(id: AIProviderID, credential: String, transport: any AITransport = URLSessionAITransport()) {
        self.id = id; self.credential = credential; self.transport = transport
    }
    public func makeRequest(_ input: AIRequest) throws -> URLRequest {
        guard id != .chatGPTSubscription else { throw AIError.unconfiguredSubscription }
        guard id == .openAIKey || id == .anthropicKey else { throw AIError.invalidRequest }
        guard !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.missingCredential }
        guard credential.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { throw AIError.invalidRequest }
        guard !input.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !input.prompt.isEmpty, (1...65536).contains(input.maximumOutputTokens) else { throw AIError.invalidRequest }
        let endpoint = id == .openAIKey ? "https://api.openai.com/v1/responses" : "https://api.anthropic.com/v1/messages"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        var body: [String: Any] = ["model": input.model, "stream": true]
        if id == .openAIKey {
            request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
            body["input"] = input.prompt; body["instructions"] = input.instructions
            body["max_output_tokens"] = input.maximumOutputTokens; body["store"] = false
        } else {
            request.setValue(credential, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body["system"] = input.instructions
            body["messages"] = [["role": "user", "content": input.prompt]]
            body["max_tokens"] = input.maximumOutputTokens
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    public func stream(_ input: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await transport.open(makeRequest(input))
                    guard (200...299).contains(response.statusCode) else { throw AIError.http(response.statusCode) }
                    var dataLines: [String] = []
                    var totalBytes = 0
                    var completed = false
                    func consume() throws -> AIEvent? {
                        guard !dataLines.isEmpty else { return nil }
                        defer { dataLines.removeAll(keepingCapacity: true) }
                        return try StreamEventDecoder.decode(dataLines.joined(separator: "\n"), provider: id)
                    }
                    for try await line in response.lines {
                        try Task.checkCancellation()
                        totalBytes += line.utf8.count
                        guard totalBytes <= 16 * 1024 * 1024 else { throw AIError.malformedStream }
                        if line.isEmpty {
                            if let event = try consume() {
                                continuation.yield(event)
                                if event == .completed { completed = true; break }
                            }
                        } else if line.hasPrefix("data:") {
                            var value = String(line.dropFirst(5))
                            if value.first == " " { value.removeFirst() }
                            dataLines.append(value)
                        }
                    }
                    if !completed, let event = try consume() {
                        continuation.yield(event); completed = event == .completed
                    }
                    guard completed else { throw AIError.incompleteResponse }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

enum StreamEventDecoder {
    static func decode(_ text: String, provider: AIProviderID) throws -> AIEvent? {
        if text == "[DONE]" { return nil } // A terminal semantic event is required.
        guard let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = object["type"] as? String else { throw AIError.malformedStream }
        switch type {
        case "error", "response.failed": throw AIError.remoteFailure
        case "response.incomplete": throw AIError.incompleteResponse
        case "response.refusal.delta", "response.refusal.done": throw AIError.remoteFailure
        case "response.output_text.delta" where provider == .openAIKey:
            guard let delta = object["delta"] as? String else { throw AIError.malformedStream }; return .textDelta(delta)
        case "response.completed" where provider == .openAIKey: return .completed
        case "content_block_delta" where provider == .anthropicKey:
            guard let delta = object["delta"] as? [String: Any] else { throw AIError.malformedStream }
            guard delta["type"] as? String == "text_delta" else { return nil }
            guard let text = delta["text"] as? String else { throw AIError.malformedStream }; return .textDelta(text)
        case "message_delta" where provider == .anthropicKey:
            if let delta = object["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String {
                if reason == "max_tokens" || reason == "pause_turn" || reason == "tool_use" { throw AIError.incompleteResponse }
                if reason == "refusal" { throw AIError.remoteFailure }
            }
            return nil
        case "message_stop" where provider == .anthropicKey: return .completed
        default: return nil
        }
    }
}
