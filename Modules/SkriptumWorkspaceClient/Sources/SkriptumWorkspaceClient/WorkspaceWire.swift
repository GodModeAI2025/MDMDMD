import Foundation
import CoreFoundation

enum WorkspaceWire {
    static func object(_ data: Data, keys: Set<String>, allowsSmallArrays: Bool = false) throws -> [String: Any] {
        guard String(data: data, encoding: .utf8) != nil else { throw WorkspaceClientError.invalidResponse }
        var parser = JSONBoundary(bytes: Array(data), allowsSmallArrays: allowsSmallArrays); try parser.validate()
        guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any], Set(result.keys) == keys else { throw WorkspaceClientError.invalidResponse }
        return result
    }
    static func boolean(_ value: Any?) throws -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw WorkspaceClientError.invalidResponse }
        return number.boolValue
    }
    static func uuid(_ value: Any?) throws -> UUID {
        guard let text = value as? String, let id = UUID(uuidString: text), text.lowercased() == id.uuidString.lowercased() else { throw WorkspaceClientError.invalidResponse }
        return id
    }
    static func envelope(_ value: Any?) throws -> WorkspaceEnvelope {
        guard let row = value as? [String: Any], Set(row.keys) == ["ciphertext", "nonce", "digest", "keyReference", "version"],
              let key = row["keyReference"] as? String,
              let version = row["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1 else { throw WorkspaceClientError.invalidResponse }
        func bytes(_ field: String) throws -> Data {
            guard let text = row[field] as? String, let bytes = Data(base64Encoded: text), bytes.base64EncodedString() == text else { throw WorkspaceClientError.invalidResponse }
            return bytes
        }
        do { return try WorkspaceEnvelope(ciphertext: bytes("ciphertext"), nonce: bytes("nonce"), digest: bytes("digest"), keyReference: key) }
        catch { throw WorkspaceClientError.invalidResponse }
    }
    static func encode(_ value: WorkspaceEnvelope) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["ciphertext": value.ciphertext.base64EncodedString(), "nonce": value.nonce.base64EncodedString(), "digest": value.digest.base64EncodedString(), "keyReference": value.keyReference, "version": value.version], options: [.sortedKeys])
    }
}
/// Bounded structural validation before Foundation materializes JSON objects.
/// Arrays are opt-in for the eight-row discovery contract only.
private struct JSONBoundary {
    let bytes: [UInt8]; var position = 0; var nodes = 0
    let allowsSmallArrays: Bool
    mutating func validate() throws {
        try value(depth: 0); space()
        guard position == bytes.count else { throw WorkspaceClientError.invalidResponse }
    }
    mutating func space() { while position < bytes.count, [9, 10, 13, 32].contains(bytes[position]) { position += 1 } }
    mutating func string() throws -> String {
        guard position < bytes.count, bytes[position] == 34 else { throw WorkspaceClientError.invalidResponse }
        let start = position; position += 1; var escaped = false
        while position < bytes.count {
            let byte = bytes[position]; position += 1
            if byte == 34 && !escaped {
                guard let string = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<position])) else { throw WorkspaceClientError.invalidResponse }
                return string
            }
            if byte == 92 && !escaped { escaped = true } else { escaped = false }
        }
        throw WorkspaceClientError.invalidResponse
    }
    mutating func value(depth: Int) throws {
        nodes += 1
        guard depth <= 4, nodes <= 64 else { throw WorkspaceClientError.invalidResponse }
        space(); guard position < bytes.count else { throw WorkspaceClientError.invalidResponse }
        if bytes[position] == 34 { _ = try string(); return }
        if bytes[position] == 91 {
            guard allowsSmallArrays else { throw WorkspaceClientError.invalidResponse }
            position += 1; space()
            if position < bytes.count, bytes[position] == 93 { position += 1; return }
            var count = 0
            while position < bytes.count {
                count += 1
                guard count <= 8 else { throw WorkspaceClientError.invalidResponse }
                try value(depth: depth + 1); space()
                guard position < bytes.count else { throw WorkspaceClientError.invalidResponse }
                let delimiter = bytes[position]; position += 1
                if delimiter == 93 { return }
                guard delimiter == 44 else { throw WorkspaceClientError.invalidResponse }
            }
            throw WorkspaceClientError.invalidResponse
        }
        if bytes[position] == 123 {
            position += 1; space(); var keys: Set<String> = []
            if position < bytes.count, bytes[position] == 125 { position += 1; return }
            while position < bytes.count {
                space(); let key = try string()
                guard key.utf8.count <= 64, keys.insert(key).inserted else { throw WorkspaceClientError.invalidResponse }
                space(); guard position < bytes.count, bytes[position] == 58 else { throw WorkspaceClientError.invalidResponse }; position += 1
                try value(depth: depth + 1); space()
                guard position < bytes.count else { throw WorkspaceClientError.invalidResponse }
                let delimiter = bytes[position]; position += 1
                if delimiter == 125 { return }
                guard delimiter == 44 else { throw WorkspaceClientError.invalidResponse }
            }
            throw WorkspaceClientError.invalidResponse
        }
        let start = position
        while position < bytes.count, ![9, 10, 13, 32, 44, 125, 93].contains(bytes[position]) { position += 1 }
        let token = String(decoding: bytes[start..<position], as: UTF8.self)
        guard ["true", "false", "null"].contains(token) || token.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else { throw WorkspaceClientError.invalidResponse }
    }
}
