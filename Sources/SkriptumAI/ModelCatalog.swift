import Foundation
#if SWIFT_PACKAGE
import SkriptumAuth
#endif

public struct AIModelChoice: Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let deprecated: Bool
}
public struct AIModelCatalog: Sendable {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil; configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 45; configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration, delegate: CatalogRedirectBlocker(), delegateQueue: nil)
    }
    public func list(provider: AIProviderID, credential: String = "", account: ChatGPTCredentials? = nil) async throws -> [AIModelChoice] {
        let url = URL(string: provider == .anthropicKey ? "https://api.anthropic.com/v1/models?limit=100" : "https://api.openai.com/v1/models")!
        var request: URLRequest
        if provider == .chatGPTSubscription {
            guard let account else { throw AIError.unconfiguredSubscription }
            request = try await account.authorizedRequest(url: url)
        } else {
            guard provider == .openAIKey || provider == .anthropicKey else { throw AIError.invalidRequest }
            guard !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.missingCredential }
            request = URLRequest(url: url)
            if provider == .anthropicKey {
                request.setValue(credential, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            } else { request.setValue("Bearer " + credential, forHTTPHeaderField: "Authorization") }
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AIError.malformedStream }
        guard response.statusCode == 200 else { throw AIError.http(response.statusCode) }
        return try Self.decode(data, provider: provider)
    }
    public static func decode(_ data: Data, provider: AIProviderID) throws -> [AIModelChoice] {
        guard data.count <= 2 * 1024 * 1024,
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = body[provider == .chatGPTSubscription ? "models" : "data"] as? [[String: Any]] else { throw AIError.malformedStream }
        var seen: Set<String> = []
        return try models.compactMap { row in
            if provider == .chatGPTSubscription, row["visibility"] as? String != "list" { return nil }
            if row["lifecycle"] as? String == "retired" { return nil }
            let field = provider == .chatGPTSubscription ? "slug" : "id"
            guard let id = row[field] as? String, !id.isEmpty else { throw AIError.malformedStream }
            guard seen.insert(id).inserted else { return nil }
            return AIModelChoice(id: id, displayName: row["display_name"] as? String ?? id, deprecated: row["lifecycle"] as? String == "deprecated")
        }
    }
}
private final class CatalogRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
