import Foundation
import Testing
@testable import SkriptumWorkspaceClient
@Test func originAndSessionBoundaries() throws {
    let origin = try WorkspaceOrigin("https://workspace.example")
    #expect(origin.url.absoluteString == "https://workspace.example")
    for value in ["http://workspace.example", "https://user:pass@workspace.example", "https://workspace.example/../x", "https://workspace.example/?x=1", "https://workspace.example/#x", "https://workspace.example/%2e%2e", "https://workspace.example/a"] {
        #expect(throws: WorkspaceClientError.invalidConfiguration) { try WorkspaceOrigin(value) }
    }
    #expect(throws: WorkspaceClientError.invalidConfiguration) { try WorkspaceOrigin.loopbackForTesting("http://remote.example:8000") }
    let credential = try WorkspaceCredential(origin: origin, accountID: UUID(), token: String(repeating: "A", count: 43))
    #expect(!String(describing: credential).contains(String(repeating: "A", count: 43)))
    #expect(!String(reflecting: credential).contains(String(repeating: "A", count: 43)))
}
@Test func envelopeBoundaries() throws {
    let value = try WorkspaceEnvelope(ciphertext: Data(repeating: 7, count: 17), nonce: Data(repeating: 1, count: 12), digest: Data(repeating: 2, count: 32), keyReference: "owned-key", version: 1)
    #expect(value.ciphertext.count == 17)
    #expect(throws: WorkspaceClientError.invalidEnvelope) { try WorkspaceEnvelope(ciphertext: Data(), nonce: value.nonce, digest: value.digest, keyReference: "k", version: 1) }
}
@Test func strictResponseWireContract() throws {
    for text in [#"{"ready":true,"ready":false}"#, #"{"ready":true,"\u0072eady":false}"#, #"{"ready":true,"role":"owner"}"#, #"{"ready":true} false"#] {
        #expect(throws: WorkspaceClientError.invalidResponse) { try WorkspaceWire.object(Data(text.utf8), keys: ["ready"]) }
    }
    #expect(throws: WorkspaceClientError.invalidResponse) { try WorkspaceWire.object(Data([0xff]), keys: ["ready"]) }
    let row: [String: Any] = ["ciphertext": Data(repeating: 1, count: 17).base64EncodedString(), "nonce": Data(repeating: 1, count: 12).base64EncodedString() + "\n", "digest": Data(repeating: 2, count: 32).base64EncodedString(), "keyReference": "k", "version": 1]
    #expect(throws: WorkspaceClientError.invalidResponse) { try WorkspaceWire.envelope(row) }
}
@Test func numericBooleanIsNotReady() throws {
    #expect(throws: WorkspaceClientError.invalidResponse) { try WorkspaceWire.boolean(NSNumber(value: 1)) }
    #expect(try WorkspaceWire.boolean(NSNumber(value: true)))
    #expect(throws: WorkspaceClientError.invalidResponse) { try WorkspaceWire.boolean("true") }
}
