import Foundation
import Testing
@testable import SkriptumAuth

struct WorkspaceAppleAuthorizationTests {
    let state = Data(repeating: 1, count: 32).base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    @Test func exactStateAndStrictUTF8() throws {
        let token = Data("e30.e30.AQ".utf8)
        let proof = try WorkspaceAppleProofValidator.make(identityToken: token, authorizationCode: Data("code".utf8), state: state, expectedState: state)
        #expect(proof.description == "WorkspaceIdentityProof(<redacted>)")
        for bad in [nil, "different", state + " "] as [String?] {
            #expect(throws: WorkspaceAppleAuthorizationError.invalidResponse) { try WorkspaceAppleProofValidator.make(identityToken: token, authorizationCode: Data("code".utf8), state: bad, expectedState: state) }
        }
        #expect(throws: WorkspaceAppleAuthorizationError.invalidResponse) { try WorkspaceAppleProofValidator.make(identityToken: Data([255]), authorizationCode: Data("code".utf8), state: state, expectedState: state) }
        #expect(throws: WorkspaceAppleAuthorizationError.invalidResponse) { try WorkspaceAppleProofValidator.make(identityToken: token, authorizationCode: Data(repeating: 65, count: 4097), state: state, expectedState: state) }
    }
    @Test func oldAttemptAndRepeatedCompletionCannotConsumeNewAttempt() {
        var first = WorkspaceAppleAttemptGate()
        let old = first.id
        let wrong = first.consume(UUID())
        let accepted = first.consume(old)
        let repeated = first.consume(old)
        #expect(!wrong)
        #expect(accepted)
        #expect(!repeated)
        var second = WorkspaceAppleAttemptGate()
        let stale = second.consume(old)
        let new = second.consume(second.id)
        let repeatedNew = second.consume(second.id)
        #expect(!stale)
        #expect(new)
        #expect(!repeatedNew)
    }
}
