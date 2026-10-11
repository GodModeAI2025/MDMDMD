import Foundation
public struct LanguageToolCheckSubmission: Sendable, Identifiable {
    public let id: UUID, endpoint: URL, language: String, document: QualityDocument
    private let permission: LanguageToolPermission
    fileprivate init(endpoint: URL, language: String, document: QualityDocument) {
        id = UUID(); self.endpoint = endpoint; self.language = language; self.document = document
        permission = LanguageToolPermission()
    }
    public func discard() { permission.discard() }
    func admit(endpoint: URL, consentID: UUID?) throws {
        guard endpoint == self.endpoint, consentID == id else { throw QualityError.contentPermissionRequired }
        try permission.claim()
    }
}
private final class LanguageToolPermission: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func claim() throws {
        try lock.withLock {
            guard !used else { throw QualityError.contentPermissionRequired }
            used = true
        }
    }
    func discard() { lock.withLock { used = true } }
}
public struct LanguageToolConfiguration: Sendable {
    public let endpoint: URL
    public init(endpoint: URL) throws {
        guard endpoint.scheme?.lowercased() == "https", endpoint.host != nil, endpoint.user == nil, endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil else { throw QualityError.invalidConfiguration }
        self.endpoint = endpoint
    }
}
public struct LanguageToolClient: Sendable {
    private let configuration: LanguageToolConfiguration
    private let transport: (@Sendable (URLRequest) async throws -> Data)?
    public init(configuration: LanguageToolConfiguration) { self.configuration = configuration; transport = nil }
    init(configuration: LanguageToolConfiguration, transport: @escaping @Sendable (URLRequest) async throws -> Data) {
        self.configuration = configuration; self.transport = transport
    }
    public func languages() async throws -> LanguageCatalog {
        let data = try await send(path: "languages", body: nil)
        return try Self.decodeLanguages(data)
    }
    static func decodeLanguages(_ data: Data) throws -> LanguageCatalog {
        guard data.count <= 2_000_000 else { throw QualityError.responseTooLarge }
        guard let values = try? JSONDecoder().decode([QualityLanguage].self, from: data), !values.isEmpty, values.count <= 300, values.allSatisfy({ !$0.code.isEmpty && $0.code.count <= 32 && !$0.longCode.isEmpty && $0.longCode.count <= 32 }) else { throw QualityError.invalidResponse }
        return LanguageCatalog(values)
    }
    public func prepare(_ document: QualityDocument, language: String) throws -> LanguageToolCheckSubmission {
        guard document.source.utf8.count <= 8 * 1024 * 1024 else { throw QualityError.inputTooLarge }
        guard !language.isEmpty, language.utf8.count <= 32 else { throw QualityError.unsupportedLanguage }
        return LanguageToolCheckSubmission(endpoint: configuration.endpoint, language: language, document: document)
    }
    @concurrent public func check(_ submission: LanguageToolCheckSubmission, consentID: UUID?,
                      progress: @MainActor @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> [QualityFinding] {
        try Task.checkCancellation()
        try submission.admit(endpoint: configuration.endpoint, consentID: consentID)
        let document = submission.document, language = submission.language
        let chunks = try await Self.chunks(document)
        await progress(0, chunks.count)
        let catalog = try await languages()
        guard catalog.languages.contains(where: { $0.longCode == language || $0.code == language }) else { throw QualityError.unsupportedLanguage }
        var findings: [QualityFinding] = []
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            var components = URLComponents()
            components.queryItems = [URLQueryItem(name: "text", value: chunk.text), URLQueryItem(name: "language", value: language)]
            // HTML form decoding treats a literal plus as space. URLComponents
            // leaves it unescaped, so encode it explicitly in both field values.
            guard let encoded = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8) else { throw QualityError.invalidRequestEncoding }
            let response = try await send(path: "check", body: encoded)
            try Task.checkCancellation()
            let values = try Self.decode(response, document: document, submittedRange: chunk.range)
            guard values.count <= 5000 - findings.count else { throw QualityError.responseTooLarge }
            findings.append(contentsOf: values)
            await progress(index + 1, chunks.count)
        }
        try Task.checkCancellation()
        return findings
    }
    @concurrent private static func chunks(_ document: QualityDocument) async throws -> [QualityTextChunk] {
        try QualityTextChunks.make(document.projection.text, preferSentences: true)
    }
    private func send(path: String, body: Data?) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: configuration.endpoint.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type") }
        if let transport {
            let data = try await transport(request)
            guard data.count <= 2_000_000 else { throw QualityError.responseTooLarge }
            return data
        }
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.urlCache = nil; sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.timeoutIntervalForRequest = 30; sessionConfiguration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: sessionConfiguration, delegate: RejectRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
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
        try decode(data, document: document, submittedRange: NSRange(location: 0, length: document.source.utf16.count))
    }
    static func decode(_ data: Data, document: QualityDocument, submittedRange: NSRange) throws -> [QualityFinding] {
        guard submittedRange.location >= 0, submittedRange.length >= 0,
              submittedRange.location <= document.source.utf16.count,
              submittedRange.length <= document.source.utf16.count - submittedRange.location else { throw QualityError.invalidRange }
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
        let projection = document.projection
        for match in response.matches {
            guard !match.rule.id.isEmpty, !match.rule.category.id.isEmpty, match.rule.category.id.count <= 256, match.rule.category.name.count <= 1024, match.offset >= 0, match.length > 0, match.offset <= submittedRange.length, match.length <= submittedRange.length - match.offset else { throw QualityError.invalidRange }
            let range = NSRange(location: submittedRange.location + match.offset, length: match.length)
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
