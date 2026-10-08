import Foundation
#if canImport(FoundationModels) && canImport(Security)
import FoundationModels
import Security

@available(iOS 27.0, macOS 27.0, *)
public struct ApplePCCProvider: AIProvider {
    public let id: AIProviderID = .applePCC
    public let capabilities = AICapabilities(textStreaming: true, requiresCredential: false, requiresApproval: true)
    private let entitlementApproved: Bool
    /// Set only for a release whose signed provisioning profile contains Apple's granted PCC entitlement.
    /// iOS has no public SecTask entitlement introspection API; the default deliberately disables PCC.
    public init(entitlementApproved: Bool? = nil) {
        self.entitlementApproved = entitlementApproved ?? (Bundle.main.object(forInfoDictionaryKey: "ScriptumPCCProvisioned") as? Bool ?? false)
    }
    public var availabilityDescription: String? {
        guard hasEntitlement else { return AIError.missingPCCEntitlement.localizedDescription }
        let model = PrivateCloudComputeLanguageModel()
        switch model.availability {
        case .available: return nil
        case .unavailable(let reason): return String(describing: reason)
        }
    }
    private var hasEntitlement: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil), let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.private-cloud-compute" as CFString, nil) as? Bool else { return false }
        return entitlementApproved && value
        #else
        return entitlementApproved
        #endif
    }
    public func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard hasEntitlement else { throw AIError.missingPCCEntitlement }
                    let model = PrivateCloudComputeLanguageModel()
                    guard model.isAvailable else { throw AIError.unavailable(String(describing: model.availability)) }
                    guard !request.prompt.isEmpty, (1...65536).contains(request.maximumOutputTokens) else { throw AIError.invalidRequest }
                    let session = LanguageModelSession(model: model, instructions: request.instructions)
                    var previous = ""
                    for try await snapshot in session.streamResponse(to: request.prompt, options: GenerationOptions(maximumResponseTokens: request.maximumOutputTokens)) {
                        try Task.checkCancellation()
                        let current = snapshot.content
                        guard current.hasPrefix(previous) else { throw AIError.malformedStream }
                        continuation.yield(.textDelta(String(current.dropFirst(previous.count))))
                        previous = current
                    }
                    continuation.yield(.completed); continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
#endif
