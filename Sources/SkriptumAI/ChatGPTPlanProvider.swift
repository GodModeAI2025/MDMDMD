import Foundation
#if SWIFT_PACKAGE
import SkriptumAuth
#endif

/// Uses the user's independently authorized ChatGPT plan. No API-key route or fallback exists here.
public struct ChatGPTPlanProvider: AIProvider {
    public let id: AIProviderID = .chatGPTSubscription
    public let capabilities = AICapabilities(textStreaming: true, requiresCredential: false, requiresApproval: true, supportsOutputTokenLimit: false)
    private let credentials: ChatGPTCredentials
    private let transport: any AITransport
    public init(credentials: ChatGPTCredentials, transport: any AITransport = URLSessionAITransport()) {
        self.credentials = credentials; self.transport = transport
    }
    public static func requestBody(_ input: AIRequest) throws -> Data {
        guard !input.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !input.prompt.isEmpty else { throw AIError.invalidRequest }
        // Plan usage preview requires complete client-side context, store:false and stream:true.
        // Do not send unsupported API-key-route fields such as max_output_tokens or previous_response_id.
        return try JSONSerialization.data(withJSONObject: [
            "model": input.model, "instructions": input.instructions,
            "input": [["role": "user", "content": input.prompt]], "store": false, "stream": true
        ])
    }
    public func stream(_ input: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        AIStreamingExecution.execute(provider: id) {
            var request = try await credentials.authorizedRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.httpBody = try Self.requestBody(input)
            return try await transport.open(request)
        }
    }
}
