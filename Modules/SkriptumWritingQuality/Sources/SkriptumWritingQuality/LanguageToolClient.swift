import Foundation
public struct LanguageToolConfiguration: Sendable {
    public let endpoint: URL
    public init(endpoint: URL) throws {
        guard endpoint.scheme?.lowercased() == "https", endpoint.host != nil, endpoint.user == nil, endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil else { throw QualityError.invalidConfiguration }
        self.endpoint = endpoint
    }
}
public struct LanguageToolClient: Sendable {
    private let configuration: LanguageToolConfiguration
    public init(configuration: LanguageToolConfiguration) { self.configuration = configuration }
    public func languages() async throws -> LanguageCatalog {
        let data = try await send(path: "languages", body: nil)
        return try Self.decodeLanguages(data)
    }
    static func decodeLanguages(_ data: Data) throws -> LanguageCatalog {
        guard data.count <= 2_000_000 else { throw QualityError.responseTooLarge }
        guard let values = try? JSONDecoder().decode([QualityLanguage].self, from: data), !values.isEmpty, values.count <= 300, values.allSatisfy({ !$0.code.isEmpty && $0.code.count <= 32 && !$0.longCode.isEmpty && $0.longCode.count <= 32 }) else { throw QualityError.invalidResponse }
        return LanguageCatalog(values)
    }
    public func check(_ document: QualityDocument, language: String) async throws -> [QualityFinding] {
        guard document.source.utf8.count <= 100_000 else { throw QualityError.inputTooLarge }
        let catalog = try await languages()
        guard catalog.languages.contains(where: { $0.longCode == language || $0.code == language }) else { throw QualityError.unsupportedLanguage }
        let text = MarkdownProjection(document.source).text
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "text", value: text), URLQueryItem(name: "language", value: language)]
        guard let encoded = components.percentEncodedQuery?.data(using: .utf8) else { throw QualityError.invalidRequestEncoding }
        let response = try await send(path: "check", body: encoded)
        try Task.checkCancellation()
        return try Self.decode(response, document: document)
    }
    private func send(path: String, body: Data?) async throws -> Data {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.urlCache = nil; sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.timeoutIntervalForRequest = 30; sessionConfiguration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: sessionConfiguration, delegate: RejectRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: configuration.endpoint.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type") }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw QualityError.invalidResponse }
        guard (200...299).contains(response.statusCode) else { throw QualityError.http(response.statusCode) }
        guard response.expectedContentLength <= 2_000_000 else { throw QualityError.responseTooLarge }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 2_000_000 else { throw QualityError.responseTooLarge }
            data.append(byte)
        }
        return data
    }
    public static func decode(_ data: Data, document: QualityDocument) throws -> [QualityFinding] {
        guard data.count <= 2_000_000 else { throw QualityError.responseTooLarge }
        struct Response: Decodable { let matches: [Match] }
        struct Match: Decodable {
            let offset: Int; let length: Int; let message: String; let replacements: [Replacement]; let rule: Rule
        }
        struct Replacement: Decodable { let value: String }
        struct Rule: Decodable { let id: String; let issueType: String; let category: Category }
        struct Category: Decodable { let id: String; let name: String }
        guard let response = try? JSONDecoder().decode(Response.self, from: data), response.matches.count <= 5000 else { throw QualityError.invalidResponse }
        var findings: [QualityFinding] = []
        let projection = MarkdownProjection(document.source)
        for match in response.matches {
            guard !match.rule.id.isEmpty, !match.rule.category.id.isEmpty, match.rule.category.id.count <= 256, match.rule.category.name.count <= 1024, match.offset >= 0, match.length > 0, match.offset <= (document.source as NSString).length, match.length <= (document.source as NSString).length - match.offset else { throw QualityError.invalidRange }
            let range = NSRange(location: match.offset, length: match.length)
            guard Range(range, in: document.source) != nil else { throw QualityError.invalidRange }
            guard projection.allows(range) else { continue }
            let kind: QualityKind
            switch match.rule.issueType {
            case "misspelling": kind = .spelling
            case "grammar", "typographical", "punctuation", "duplication", "inconsistency", "uncategorized": kind = .grammar
            case "style", "register", "locale", "characters", "terminology", "formatting", "other": kind = .style
            default: throw QualityError.invalidResponse
            }
            findings.append(try QualityFinding.make(document: document, range: range, message: match.message, replacements: match.replacements.map(\.value), ruleID: match.rule.id, kind: kind, engine: "Eigener LanguageTool-Regelserver"))
        }
        return findings
    }
}
private extension QualityError { static var invalidRequestEncoding: QualityError { .invalidConfiguration } }
private final class RejectRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
