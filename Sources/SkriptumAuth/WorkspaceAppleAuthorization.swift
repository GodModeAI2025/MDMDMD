import Foundation
#if canImport(SkriptumWorkspaceClient)
import SkriptumWorkspaceClient
#endif

public enum WorkspaceAppleAuthorizationError: Error, Equatable, Sendable {
    case busy, cancelled, expired, invalidResponse, unavailable
}

struct WorkspaceAppleAttemptGate {
    let id = UUID()
    private var pending = true
    mutating func consume(_ candidate: UUID) -> Bool {
        guard pending, candidate == id else { return false }
        pending = false
        return true
    }
}

enum WorkspaceAppleProofValidator {
    static func make(identityToken: Data?, authorizationCode: Data?, state: String?, expectedState: String) throws -> WorkspaceIdentityProof {
        guard let state, state.utf8.elementsEqual(expectedState.utf8),
              let identityToken, (1...16_384).contains(identityToken.count),
              let authorizationCode, (1...4096).contains(authorizationCode.count),
              let token = String(data: identityToken, encoding: .utf8),
              let code = String(data: authorizationCode, encoding: .utf8) else { throw WorkspaceAppleAuthorizationError.invalidResponse }
        do { return try WorkspaceIdentityProof(identityToken: token, authorizationCode: code, state: state) }
        catch { throw WorkspaceAppleAuthorizationError.invalidResponse }
    }
}

#if canImport(UIKit)
import UIKit
import AuthenticationServices

/// Acquires proof only. It neither creates a server session nor persists credentials.
@MainActor public final class WorkspaceAppleAuthorization: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    private var controller: ASAuthorizationController?
    private var gate: WorkspaceAppleAttemptGate?
    private var expectedState: String?
    private var continuation: CheckedContinuation<WorkspaceIdentityProof, any Error>?
    private var timeout: Task<Void, Never>?
    private var sceneObserver: (any NSObjectProtocol)?
    public init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { anchor }

    public func authorize(_ challenge: WorkspaceIdentityChallenge) async throws -> WorkspaceIdentityProof {
        guard gate == nil else { throw WorkspaceAppleAuthorizationError.busy }
        guard let scene = anchor.windowScene, scene.activationState == .foregroundActive else {
            throw WorkspaceAppleAuthorizationError.unavailable
        }
        let clock = ContinuousClock()
        let observedAt = clock.now
        let remaining = min(Duration.seconds(300), challenge.remainingLifetime)
        let expiration = observedAt.advanced(by: remaining)
        guard remaining > .zero else { throw WorkspaceAppleAuthorizationError.expired }
        try Task.checkCancellation()
        let attempt = WorkspaceAppleAttemptGate()
        gate = attempt
        expectedState = challenge.state
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending in
                continuation = pending
                let request = ASAuthorizationAppleIDProvider().createRequest()
                request.nonce = challenge.nonce
                request.state = challenge.state
                let next = ASAuthorizationController(authorizationRequests: [request])
                controller = next
                next.delegate = self
                next.presentationContextProvider = self
                sceneObserver = NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification, object: scene, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.finish(.failure(WorkspaceAppleAuthorizationError.cancelled), attemptID: attempt.id) }
                }
                timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(until: expiration, clock: clock) }
                    catch { return }
                    self?.finish(.failure(WorkspaceAppleAuthorizationError.expired), attemptID: attempt.id)
                }
                next.performRequests()
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.finish(.failure(WorkspaceAppleAuthorizationError.cancelled), attemptID: attempt.id) }
        }
    }
    public func cancel() {
        guard let id = gate?.id else { return }
        finish(.failure(WorkspaceAppleAuthorizationError.cancelled), attemptID: id)
    }
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard controller === self.controller, let id = gate?.id, let expectedState else { return }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(.failure(WorkspaceAppleAuthorizationError.invalidResponse), attemptID: id)
            return
        }
        let result = Result { try WorkspaceAppleProofValidator.make(identityToken: credential.identityToken, authorizationCode: credential.authorizationCode, state: credential.state, expectedState: expectedState) }
        finish(result, attemptID: id)
    }
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        guard controller === self.controller, let id = gate?.id else { return }
        let controlled: WorkspaceAppleAuthorizationError = (error as? ASAuthorizationError)?.code == .canceled ? .cancelled : .unavailable
        finish(.failure(controlled), attemptID: id)
    }
    private func finish(_ result: Result<WorkspaceIdentityProof, any Error>, attemptID: UUID) {
        guard gate?.consume(attemptID) == true else { return }
        let pending = continuation
        let previous = controller
        continuation = nil; controller = nil; gate = nil; expectedState = nil
        timeout?.cancel(); timeout = nil
        if let sceneObserver { NotificationCenter.default.removeObserver(sceneObserver) }
        sceneObserver = nil
        previous?.delegate = nil; previous?.presentationContextProvider = nil
        previous?.cancel()
        pending?.resume(with: result)
    }
}
#endif
