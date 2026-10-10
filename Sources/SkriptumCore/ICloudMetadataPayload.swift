import Foundation
import CryptoKit

public enum ICloudMetadataMergeError: Error, Equatable, Sendable {
    case invalidPayload, unsupportedKind, identityMismatch, revisionMismatch, immutableRevision
}

/// Causal document metadata. Its digest is byte-exact sorted JSON, never a
/// timestamp comparison or a credential. Version 1 always includes baseDigest.
public struct ICloudMetadataPayload<Value: Codable & Sendable>: Codable, Sendable {
    public let schemaVersion: Int
    public let value: Value
    public let baseDigest: String?
    private enum Keys: String, CodingKey { case schemaVersion, value, baseDigest }
    private struct RawKey: CodingKey {
        let stringValue: String; let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    public init(value: Value, baseDigest: String?) throws {
        try Self.validate(baseDigest)
        schemaVersion = 1; self.value = value; self.baseDigest = baseDigest
    }
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.container(keyedBy: RawKey.self)
        guard Set(raw.allKeys.map(\.stringValue)) == ["schemaVersion", "value", "baseDigest"] else { throw ICloudMetadataMergeError.invalidPayload }
        let values = try decoder.container(keyedBy: Keys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 else { throw ICloudMetadataMergeError.invalidPayload }
        value = try values.decode(Value.self, forKey: .value)
        baseDigest = try values.decodeIfPresent(String.self, forKey: .baseDigest)
        try Self.validate(baseDigest)
    }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion); try values.encode(value, forKey: .value)
        if let baseDigest { try values.encode(baseDigest, forKey: .baseDigest) }
        else { try values.encodeNil(forKey: .baseDigest) }
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(self)
        guard bytes.count <= 8 * 1024 * 1024 else { throw ICloudMetadataMergeError.invalidPayload }
        return bytes
    }
    public static func decode(_ bytes: Data) throws -> Self {
        guard bytes.count <= 8 * 1024 * 1024 else { throw ICloudMetadataMergeError.invalidPayload }
        do {
            let value = try JSONDecoder().decode(Self.self, from: bytes)
            // Version 1 writers produce canonical sorted JSON. Comparing exact
            // bytes rejects duplicate-key folding and ignored unknown value fields.
            guard try value.encoded() == bytes else { throw ICloudMetadataMergeError.invalidPayload }
            return value
        }
        catch { throw ICloudMetadataMergeError.invalidPayload }
    }
    public static func valueBytes(_ value: Value) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    public static func digest(of value: Value) throws -> String {
        SHA256.hash(data: try valueBytes(value)).map { String(format: "%02x", $0) }.joined()
    }
    /// Includes causal ancestry: identical values based on different versions
    /// cannot share an acknowledgement identity while their payloads differ.
    public func revisionID() throws -> UUID {
        var bytes = Array(SHA256.hash(data: try encoded()).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    private static func validate(_ digest: String?) throws {
        guard digest.map({ $0.utf8.count == 64 && $0.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) }) ?? true else {
            throw ICloudMetadataMergeError.invalidPayload
        }
    }
}
