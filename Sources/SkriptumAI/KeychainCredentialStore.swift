import Foundation
#if canImport(Security)
import Security

/// Device-bound credentials are excluded from iCloud sync, document packages and backups.
public struct KeychainCredentialStore: Sendable {
    public let service: String
    public init(service: String = "app.skriptum.credentials") { self.service = service }
    public func read(for provider: AIProviderID) throws -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialError(status: status) }
        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else { throw CredentialError(status: errSecDecode) }
        return secret
    }
    public func save(_ secret: String, for provider: AIProviderID) throws {
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.missingCredential }
        let query = baseQuery(provider)
        let attributes: [String: Any] = [kSecValueData as String: Data(secret.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let insertion = query.merging(attributes) { _, new in new }
            let addStatus = SecItemAdd(insertion as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw CredentialError(status: addStatus) }
        } else if status != errSecSuccess { throw CredentialError(status: status) }
    }
    public func delete(for provider: AIProviderID) throws {
        let status = SecItemDelete(baseQuery(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError(status: status) }
    }
    private func baseQuery(_ provider: AIProviderID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: provider.rawValue, kSecAttrSynchronizable as String: false]
    }
}
public struct CredentialError: Error, Sendable, LocalizedError {
    public let status: OSStatus
    public var errorDescription: String? { "Der Schlüsselbund ist nicht zugänglich (\(status))." }
}
#endif
