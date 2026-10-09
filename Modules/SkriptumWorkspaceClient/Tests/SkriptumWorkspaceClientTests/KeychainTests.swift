import Foundation
import Testing
#if canImport(Security)
import Security
@testable import SkriptumWorkspaceClient

@Test func workspaceKeychainProfileAdmission() async throws {
    #expect(throws: WorkspaceCredentialStoreError.invalidProfile) { try WorkspaceKeychainCredentialStore(profileID: "") }
    let origin = try WorkspaceOrigin("https://workspace.example")
    let account = UUID()
    let store = try WorkspaceKeychainCredentialStore(profileID: "apple-native", service: "test.scriptum.workspace." + UUID().uuidString)
    let unbound = try WorkspaceCredential(origin: origin, accountID: account, token: String(repeating: "A", count: 43))
    do { try await store.save(unbound); Issue.record("Unbound credential persisted") }
    catch { #expect(error as? WorkspaceCredentialStoreError == .profileMismatch) }
    let other = try WorkspaceCredential(origin: origin, accountID: account, token: String(repeating: "A", count: 43), profileID: "other")
    do { try await store.save(other); Issue.record("Different profile persisted") }
    catch { #expect(error as? WorkspaceCredentialStoreError == .profileMismatch) }
}
#endif
#if canImport(Security)
@Test func workspaceKeychainQueriesAreExactlyScoped() throws {
    let origin = try WorkspaceOrigin("https://workspace.example")
    let account = UUID()
    let first = try WorkspaceKeychainCredentialStore(profileID: "profile-a", service: "test.scriptum.workspace.scopes")
    let second = try WorkspaceKeychainCredentialStore(profileID: "profile-b", service: "test.scriptum.workspace.scopes")
    let a = first.base(origin: origin, accountID: account)
    let b = second.base(origin: origin, accountID: account)
    #expect(a[kSecAttrAccount as String] as? String != b[kSecAttrAccount as String] as? String)
    #expect(a[kSecAttrAccount as String] as? String != first.base(origin: origin, accountID: UUID())[kSecAttrAccount as String] as? String)
    let otherOrigin = try WorkspaceOrigin("https://other.example")
    #expect(a[kSecAttrAccount as String] as? String != first.base(origin: otherOrigin, accountID: account)[kSecAttrAccount as String] as? String)
    #expect(a[kSecAttrSynchronizable as String] as? Bool == false)
    #expect(a[kSecUseDataProtectionKeychain as String] as? Bool == true)
    #expect(a[kSecAttrAccessGroup as String] == nil)
}
#endif
