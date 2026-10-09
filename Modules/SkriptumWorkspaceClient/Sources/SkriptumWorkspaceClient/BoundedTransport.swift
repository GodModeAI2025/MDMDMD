import Foundation

struct WorkspaceHTTPResponse: @unchecked Sendable { let response: HTTPURLResponse; let data: Data }
/// One delegate per request; every mutable field is owned by its lock.
final class BoundedTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<WorkspaceHTTPResponse, any Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var stopped = false
    private var cancelled = false
    private let limit: Int
    #if DEBUG && SWIFT_PACKAGE
    private let verificationTLSAnchor: WorkspaceVerificationTLSAnchor?
    init(limit: Int, verificationTLSAnchor: WorkspaceVerificationTLSAnchor?) {
        self.limit = limit; self.verificationTLSAnchor = verificationTLSAnchor
    }
    #endif
    init(limit: Int) {
        self.limit = limit
        #if DEBUG && SWIFT_PACKAGE
        verificationTLSAnchor = nil
        #endif
    }
    func run(_ request: URLRequest) async throws -> WorkspaceHTTPResponse {
        #if DEBUG && SWIFT_PACKAGE
        if let verificationTLSAnchor, !verificationTLSAnchor.permits(request.url) { throw WorkspaceClientError.transport }
        #endif
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in start(request, continuation) }
        } onCancel: { self.cancel() }
    }
    private func start(_ request: URLRequest, _ next: CheckedContinuation<WorkspaceHTTPResponse, any Error>) {
        lock.lock()
        if cancelled { lock.unlock(); next.resume(throwing: WorkspaceClientError.cancelled); return }
        continuation = next
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCache = nil; configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 5; configuration.timeoutIntervalForResource = 10
        let created = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        session = created; let createdTask = created.dataTask(with: request); task = createdTask
        lock.unlock(); createdTask.resume()
    }
    private func cancel() { lock.lock(); cancelled = true; lock.unlock(); finish(.failure(WorkspaceClientError.cancelled)) }
    private func finish(_ result: Result<WorkspaceHTTPResponse, any Error>) {
        lock.lock()
        guard !stopped, let next = continuation else { lock.unlock(); return }
        stopped = true; continuation = nil
        let active = session; session = nil; task = nil
        lock.unlock()
        active?.invalidateAndCancel(); next.resume(with: result)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil); finish(.failure(WorkspaceClientError.redirectDenied))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        #if DEBUG && SWIFT_PACKAGE
        if let verificationTLSAnchor {
            if verificationTLSAnchor.accepts(challenge, requestURL: task.originalRequest?.url), let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                finish(.failure(WorkspaceClientError.transport))
            }
            return
        }
        #endif
        // Preserve normal platform TLS trust. Never answer HTTP credential challenges.
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust { completionHandler(.performDefaultHandling, nil) }
        else { completionHandler(.cancelAuthenticationChallenge, nil); finish(.failure(WorkspaceClientError.transport)) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse,
              http.allHeaderFields.reduce(0, { $0 + String(describing: $1.key).utf8.count + String(describing: $1.value).utf8.count }) <= 8192 else {
            completionHandler(.cancel); finish(.failure(WorkspaceClientError.invalidResponse)); return
        }
        guard response.expectedContentLength <= Int64(limit) else { completionHandler(.cancel); finish(.failure(WorkspaceClientError.oversized)); return }
        lock.lock(); self.response = http; lock.unlock(); completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive incoming: Data) {
        lock.lock()
        if stopped { lock.unlock(); return }
        guard incoming.count <= limit - data.count else { lock.unlock(); finish(.failure(WorkspaceClientError.oversized)); return }
        data.append(incoming); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock(); let current = response; let bytes = data; lock.unlock()
        if error != nil { finish(.failure(WorkspaceClientError.transport)) }
        else if let current { finish(.success(WorkspaceHTTPResponse(response: current, data: bytes))) }
        else { finish(.failure(WorkspaceClientError.invalidResponse)) }
    }
}
