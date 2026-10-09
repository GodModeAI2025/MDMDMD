import Foundation
import Security

/// Synthetic, uniquely namespaced actual Security operations. No token output.
func runWorkspaceKeychainProbe() async throws -> Int {
    let service = "test.scriptum.workspace." + UUID().uuidString
    let origin = try WorkspaceOrigin("https://workspace-proof.example")
    let otherOrigin = try WorkspaceOrigin("https://other-proof.example")
    let account = UUID(), otherAccount = UUID()
    let a = try WorkspaceKeychainCredentialStore(profileID: "profile-a", service: service)
    let b = try WorkspaceKeychainCredentialStore(profileID: "profile-b", service: service)
    let tokenA = String(repeating: "A", count: 43), tokenB = String(repeating: "B", count: 43), tokenC = String(repeating: "C", count: 43)
    let first = try WorkspaceCredential(origin: origin, accountID: account, token: tokenA, profileID: "profile-a")
    let second = try WorkspaceCredential(origin: origin, accountID: account, token: tokenB, profileID: "profile-b")
    var checks = 0
    func require(_ condition: Bool) throws { guard condition else { throw WorkspaceCredentialStoreError.invalidRecord }; checks += 1 }
    do {
        try require(try await a.load(origin: origin, accountID: account) == nil)
        try await a.save(first); try await b.save(second)
        try require(try await a.load(origin: origin, accountID: account)?.token == tokenA)
        try require(try await b.load(origin: origin, accountID: account)?.token == tokenB)
        let reopened = try WorkspaceKeychainCredentialStore(profileID: "profile-a", service: service)
        try require(try await reopened.load(origin: origin, accountID: account)?.token == tokenA)
        try require(try await a.load(origin: otherOrigin, accountID: account) == nil)
        try require(try await a.load(origin: origin, accountID: otherAccount) == nil)
        try await a.save(WorkspaceCredential(origin: origin, accountID: account, token: tokenC, profileID: "profile-a"))
        try require(try await reopened.load(origin: origin, accountID: account)?.token == tokenC)
        try require(try await b.load(origin: origin, accountID: account)?.token == tokenB)
        var query = a.base(origin: origin, accountID: account)
        query[kSecReturnAttributes as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw WorkspaceCredentialStoreError.keychainStatus(status) }
        let attributes = result as? [String: Any]
        try require(attributes?[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        try require(attributes?[kSecAttrSynchronizable as String] as? Bool == false)
        let malformed = Data("malformed-record".utf8)
        let updated = SecItemUpdate(a.base(origin: origin, accountID: account) as CFDictionary, [kSecValueData as String: malformed] as CFDictionary)
        guard updated == errSecSuccess else { throw WorkspaceCredentialStoreError.keychainStatus(updated) }
        do { _ = try await a.load(origin: origin, accountID: account); throw WorkspaceClientError.invalidResponse }
        catch WorkspaceCredentialStoreError.invalidRecord { checks += 1 }
        var raw = a.base(origin: origin, accountID: account); raw[kSecReturnData as String] = true; raw[kSecMatchLimit as String] = kSecMatchLimitOne
        var bytes: CFTypeRef?
        let copied = SecItemCopyMatching(raw as CFDictionary, &bytes)
        guard copied == errSecSuccess else { throw WorkspaceCredentialStoreError.keychainStatus(copied) }
        try require(bytes as? Data == malformed)
        try await a.save(first)
        try await a.remove(origin: origin, accountID: account)
        try require(try await a.load(origin: origin, accountID: account) == nil)
        try await a.remove(origin: origin, accountID: account); checks += 1
        try require(try await b.load(origin: origin, accountID: account)?.token == tokenB)
        try await b.remove(origin: origin, accountID: account)
        try require(try await b.load(origin: origin, accountID: account) == nil)
    } catch {
        try? await a.remove(origin: origin, accountID: account)
        try? await b.remove(origin: origin, accountID: account)
        throw error
    }
    return checks
}
