import Foundation
#if canImport(Security)
import Security
import CryptoKit
import LocalAuthentication

public enum WorkspaceCredentialStoreError: Error, Equatable, Sendable {
    case invalidProfile, invalidService, profileMismatch, invalidRecord
    case keychainStatus(Int32)
}

/// One explicitly configured identity profile; no account/profile enumeration or
/// fallback. Sessions never synchronize or migrate to another device.
public actor WorkspaceKeychainCredentialStore: WorkspaceCredentialStore {
    public let profileID: String
    public let service: String
    public init(profileID: String, service: String = "app.scriptum.workspace.sessions.v1") throws {
        guard WorkspaceCredential.validProfile(profileID) else { throw WorkspaceCredentialStoreError.invalidProfile }
        guard (1...128).contains(service.utf8.count), service.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0) }) else { throw WorkspaceCredentialStoreError.invalidService }
        self.profileID = profileID; self.service = service
    }
    public func load(origin: WorkspaceOrigin, accountID: UUID) async throws -> WorkspaceCredential? {
        var query = base(origin: origin, accountID: accountID)
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw WorkspaceCredentialStoreError.keychainStatus(status) }
        guard let attributes = result as? [String: Any], let data = attributes[kSecValueData as String] as? Data,
              data.count <= 2048,
              let accessibility = attributes[kSecAttrAccessible as String] as? String,
              accessibility == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String),
              let sync = attributes[kSecAttrSynchronizable as String] as? NSNumber, !sync.boolValue,
              (try? WorkspaceWire.object(data, keys: ["schemaVersion", "origin", "accountID", "profileID", "token"])) != nil,
              let record = try? JSONDecoder().decode(Record.self, from: data), record.schemaVersion == 1,
              record.origin.utf8.elementsEqual(origin.url.absoluteString.utf8), record.accountID == accountID,
              record.profileID.utf8.elementsEqual(profileID.utf8),
              let credential = try? WorkspaceCredential(origin: origin, accountID: accountID, token: record.token, profileID: profileID) else { throw WorkspaceCredentialStoreError.invalidRecord }
        return credential
    }
    public func save(_ credential: WorkspaceCredential) async throws {
        guard credential.profileID == profileID else { throw WorkspaceCredentialStoreError.profileMismatch }
        let record = Record(schemaVersion: 1, origin: credential.origin.url.absoluteString, accountID: credential.accountID, profileID: profileID, token: credential.token)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        guard data.count <= 2048 else { throw WorkspaceCredentialStoreError.invalidRecord }
        let query = base(origin: credential.origin, accountID: credential.accountID)
        let updates: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        for _ in 0..<3 {
            let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
            if status == errSecSuccess { return }
            guard status == errSecItemNotFound else { throw WorkspaceCredentialStoreError.keychainStatus(status) }
            let insertion = query.merging(updates) { _, new in new }
            let added = SecItemAdd(insertion as CFDictionary, nil)
            if added == errSecSuccess { return }
            guard added == errSecDuplicateItem else { throw WorkspaceCredentialStoreError.keychainStatus(added) }
        }
        throw WorkspaceCredentialStoreError.keychainStatus(errSecDuplicateItem)
    }
    public func remove(origin: WorkspaceOrigin, accountID: UUID) async throws {
        let query = base(origin: origin, accountID: accountID)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw WorkspaceCredentialStoreError.keychainStatus(status) }
    }
    /// Internal only so actual Security probes can inspect the exact attributes.
    nonisolated func base(origin: WorkspaceOrigin, accountID: UUID) -> [String: Any] {
        var bytes = Data()
        for field in [origin.url.absoluteString, profileID, accountID.uuidString] {
            let data = Data(field.utf8)
            bytes.append(contentsOf: String(data.count).utf8); bytes.append(58); bytes.append(data)
        }
        let scope = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let context = LAContext(); context.interactionNotAllowed = true
        return [kSecUseAuthenticationContext as String: context, kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: scope, kSecAttrSynchronizable as String: false,
                kSecUseDataProtectionKeychain as String: true]
    }
    private struct Record: Codable {
        let schemaVersion: Int; let origin: String; let accountID: UUID
        let profileID: String; let token: String
    }
}
#endif
