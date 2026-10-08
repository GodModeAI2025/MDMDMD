import Foundation
import Testing
@testable import SkriptumAI

@Test func requestContracts() throws {
    let input = AIRequest(model: "chosen-model", instructions: "Preserve meaning", prompt: "Hallo", maximumOutputTokens: 256)
    let open = try RemoteAIProvider(id: .openAIKey, credential: "secret").makeRequest(input)
    #expect(open.url?.absoluteString == "https://api.openai.com/v1/responses")
    #expect(open.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    let data = try #require(open.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(body["store"] as? Bool == false)
    #expect(body["stream"] as? Bool == true)
    #expect(body["input"] as? String == "Hallo")
    let claude = try RemoteAIProvider(id: .anthropicKey, credential: "secret").makeRequest(input)
    #expect(claude.value(forHTTPHeaderField: "x-api-key") == "secret")
    #expect(claude.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    #expect(claude.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test func semanticStreaming() throws {
    #expect(try StreamEventDecoder.decode("{\"type\":\"response.output_text.delta\",\"delta\":\"Grüße\"}", provider: .openAIKey) == .textDelta("Grüße"))
    #expect(try StreamEventDecoder.decode("{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Text\"}}", provider: .anthropicKey) == .textDelta("Text"))
    #expect(try StreamEventDecoder.decode("{\"type\":\"ping\"}", provider: .anthropicKey) == nil)
    #expect(throws: AIError.self) { try StreamEventDecoder.decode("{\"type\":\"response.incomplete\"}", provider: .openAIKey) }
    #expect(throws: AIError.self) { try StreamEventDecoder.decode("{\"type\":\"error\",\"error\":{\"message\":\"overloaded\"}}", provider: .anthropicKey) }
}

@Test func noCredentialOrOAuthFallback() {
    #expect(throws: AIError.self) { try RemoteAIProvider(id: .openAIKey, credential: " ").makeRequest(AIRequest(model: "x", prompt: "text")) }
    #expect(throws: AIError.self) { try RemoteAIProvider(id: .chatGPTSubscription, credential: "anything").makeRequest(AIRequest(model: "x", prompt: "text")) }
}

private struct FakeTransport: AITransport {
    let status: Int
    let lines: [String]
    func open(_ request: URLRequest) async throws -> AIHTTPStream {
        AIHTTPStream(statusCode: status, lines: AsyncThrowingStream { continuation in
            for line in lines { continuation.yield(line) }
            continuation.finish()
        })
    }
}

@Test func endToEndStreamAndHTTPFailure() async throws {
    let adapter = RemoteAIProvider(id: .openAIKey, credential: "test", transport: FakeTransport(status: 200, lines: ["data: {\"type\":\"response.output_text.delta\",\"delta\":\"A\"}", "", "data: {\"type\":\"response.completed\"}", ""]))
    var events: [AIEvent] = []
    for try await event in adapter.stream(AIRequest(model: "test", prompt: "input")) { events.append(event) }
    #expect(events == [.textDelta("A"), .completed])
    let failing = RemoteAIProvider(id: .anthropicKey, credential: "test", transport: FakeTransport(status: 429, lines: []))
    await #expect(throws: AIError.self) { for try await _ in failing.stream(AIRequest(model: "test", prompt: "input")) {} }
    let truncated = RemoteAIProvider(id: .openAIKey, credential: "test", transport: FakeTransport(status: 200, lines: ["data: {\"type\":\"response.output_text.delta\",\"delta\":\"A\"}", ""]))
    await #expect(throws: AIError.self) { for try await _ in truncated.stream(AIRequest(model: "test", prompt: "input")) {} }
}
