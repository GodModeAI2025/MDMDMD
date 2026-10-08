#if canImport(UIKit)
import Foundation
import UIKit
import AuthenticationServices
import Network

/// Presents the OS-owned consent flow. A real account/browser callback remains a release acceptance gate.
/// OpenAI mandates HTTP loopback; Apple's current callback API supports custom schemes and HTTPS only,
/// so the still-supported nil-scheme initializer keeps the browser alive while Network receives loopback.
@MainActor
public final class NativeChatGPTSignInCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let credentials: ChatGPTCredentials
    private let anchor: ASPresentationAnchor
    private var browser: ASWebAuthenticationSession?
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URL, Error>?
    private var portContinuation: CheckedContinuation<UInt16, Error>?
    private var pendingAttempt: OAuthAttempt?
    private var timeout: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var signingIn = false
    private var completionTask: Task<ChatGPTAccount, Error>?
    public init(credentials: ChatGPTCredentials, anchor: ASPresentationAnchor) { self.credentials = credentials; self.anchor = anchor }
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
    public func signIn(addAccount: Bool = false) async throws -> ChatGPTAccount {
        guard !signingIn else { throw AuthError.browserUnavailable }
        signingIn = true; generation &+= 1
        let run = generation
        defer { signingIn = false }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        parameters.allowLocalEndpointReuse = false
        let listener: NWListener
        do { listener = try NWListener(using: parameters) }
        catch { throw Self.listenerError(error) }
        self.listener = listener
        // Network requires this handler before start, including while readiness is pending.
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self, self.generation == run, let attempt = self.pendingAttempt else { connection.cancel(); return }
                self.receive(connection, attempt: attempt)
            }
        }
        defer { cleanup() }
        let port: UInt16 = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { readyContinuation in
                portContinuation = readyContinuation
                listener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        guard let self, self.generation == run else { return }
                        switch state {
                        case .ready:
                            if let port = self.listener?.port { self.finishPort(.success(port.rawValue)) }
                            else { self.finishPort(.failure(AuthError.listenerFailed)) }
                        case .failed(let error): self.finishPort(.failure(Self.listenerError(error)))
                        case .cancelled: self.finishPort(.failure(AuthError.cancelled))
                        default: break
                        }
                    }
                }
                listener.start(queue: .main)
            }
        } onCancel: { [weak self] in Task { @MainActor in self?.cancel() } }
        try Task.checkCancellation()
        guard generation == run else { throw AuthError.cancelled }
        let attempt = try await credentials.makeAttempt(port: port, addAccount: addAccount)
        try Task.checkCancellation()
        guard generation == run else { throw AuthError.cancelled }
        pendingAttempt = attempt
        let url = await credentials.authorizationURL(for: attempt)
        try Task.checkCancellation()
        guard generation == run else { throw AuthError.cancelled }
        let callback: URL = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { callbackContinuation in
                continuation = callbackContinuation
                // No invented custom callback scheme: the exact loopback request reaches the listener.
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { [weak self] _, error in
                    Task { @MainActor in
                        if let error, self?.generation == run {
                            let nsError = error as NSError
                            let failure: AuthError = nsError.domain == ASWebAuthenticationSessionErrorDomain && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue ? .cancelled : .browserFailure(nsError.code)
                            self?.finish(.failure(failure))
                        }
                    }
                }
                browser = session
                session.presentationContextProvider = self
                if !session.start() { finish(.failure(AuthError.browserUnavailable)) }
                timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(600))
                    guard !Task.isCancelled else { return }
                    self?.finish(.failure(AuthError.expiredAttempt))
                }
            }
        } onCancel: { [weak self] in Task { @MainActor in self?.finish(.failure(AuthError.cancelled)) } }
        try Task.checkCancellation()
        guard generation == run else { throw AuthError.cancelled }
        let completion = Task { try await credentials.complete(callback, attempt: attempt) }
        completionTask = completion
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await completion.value
        } onCancel: { completion.cancel() }
    }
    private static func listenerError(_ error: Error) -> AuthError {
        guard let networkError = error as? NWError else { return .listenerFailed }
        switch networkError {
        case .posix(let code): return .listenerFailure(domain: "POSIX", code: code.rawValue)
        case .dns(let code): return .listenerFailure(domain: "DNS", code: code)
        case .tls(let code): return .listenerFailure(domain: "TLS", code: code)
        case .wifiAware: return .listenerFailure(domain: "WIFI-AWARE", code: 0)
        @unknown default: return .listenerFailed
        }
    }
    public func cancel() {
        generation &+= 1
        completionTask?.cancel()
        finishPort(.failure(AuthError.cancelled))
        finish(.failure(AuthError.cancelled))
        cleanup()
    }
    private func finishPort(_ result: Result<UInt16, Error>) {
        guard let portContinuation else { return }
        self.portContinuation = nil
        portContinuation.resume(with: result)
    }
    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
        timeout?.cancel(); browser?.cancel(); browser = nil; listener?.cancel(); listener = nil
    }
    private func cleanup() {
        finishPort(.failure(AuthError.cancelled))
        completionTask?.cancel(); completionTask = nil
        timeout?.cancel(); timeout = nil; browser?.cancel(); browser = nil; listener?.cancel(); listener = nil; pendingAttempt = nil
    }
    private func receive(_ connection: NWConnection, attempt: OAuthAttempt) {
        connection.start(queue: .main)
        receiveChunk(connection, attempt: attempt, buffer: Data())
    }
    private func receiveChunk(_ connection: NWConnection, attempt: OAuthAttempt, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard self?.pendingAttempt?.state == attempt.state else { connection.cancel(); return }
                let buffer = buffer + (data ?? Data())
                guard buffer.count <= 16384, error == nil else { connection.cancel(); return }
                guard let text = String(data: buffer, encoding: .utf8), text.contains("\r\n\r\n") else {
                    if complete { connection.cancel() } else { self?.receiveChunk(connection, attempt: attempt, buffer: buffer) }
                    return
                }
                let line = text.components(separatedBy: "\r\n").first ?? ""
                let fields = line.split(separator: " ")
                guard fields.count == 3, fields[0] == "GET", fields[2] == "HTTP/1.1", fields[1].hasPrefix("/auth/callback?"),
                      let url = URL(string: "http://127.0.0.1:\(attempt.redirectURI.port! )" + fields[1]) else { connection.cancel(); return }
                do {
                    _ = try attempt.parseCallback(url)
                    let body = "ChatGPT sign-in received. You may return to Scriptum."
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                    self?.finish(.success(url))
                } catch AuthError.denied {
                    connection.cancel(); self?.finish(.failure(AuthError.denied))
                } catch {
                    // Untrusted local requests cannot terminate another pending sign-in.
                    connection.cancel()
                }
            }
        }
    }
}
#endif
