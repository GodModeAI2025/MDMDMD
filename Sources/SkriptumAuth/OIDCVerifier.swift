import Foundation
import Security

public nonisolated struct VerifiedIdentity: Codable, Sendable, Equatable {
    public let issuer: String
    public let subject: String
    public let email: String?
}

/// RS256 only. Claims become identity only after the cryptographic signature is verified.
public nonisolated enum OIDCVerifier {
    public static func verify(token: String, jwks: Data, clientID: String, nonce: String?, now: Date = Date()) throws -> VerifiedIdentity {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let headerData = Data(base64URL: parts[0]), let claimsData = Data(base64URL: parts[1]), let signature = Data(base64URL: parts[2]),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any], header["alg"] as? String == "RS256",
              header["crit"] == nil, let kid = header["kid"] as? String,
              let root = try? JSONSerialization.jsonObject(with: jwks) as? [String: Any], let keys = root["keys"] as? [[String: Any]] else { throw AuthError.invalidSignature }
        let matches = keys.filter { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" }
        guard matches.count == 1, let jwk = matches.first, (jwk["use"] as? String ?? "sig") == "sig", (jwk["alg"] as? String ?? "RS256") == "RS256",
              let n = jwk["n"] as? String, let e = jwk["e"] as? String, let modulus = Data(base64URL: n), let exponent = Data(base64URL: e), modulus.count >= 256 else { throw AuthError.invalidSignature }
        let keyData = der(0x30, derInteger(modulus) + derInteger(exponent))
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, nil),
              SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data("\(parts[0]).\(parts[1])".utf8) as CFData, signature as CFData, nil) else { throw AuthError.invalidSignature }
        guard let claims = try? JSONSerialization.jsonObject(with: claimsData) as? [String: Any],
              claims["iss"] as? String == "https://auth.openai.com", let sub = claims["sub"] as? String, !sub.isEmpty,
              let exp = claims["exp"] as? Double, let iat = claims["iat"] as? Double,
              exp > now.timeIntervalSince1970 - 5, iat <= now.timeIntervalSince1970 + 5 else { throw AuthError.invalidIdentity }
        let audiences = (claims["aud"] as? [String]) ?? (claims["aud"] as? String).map { [$0] } ?? []
        guard audiences.contains(clientID), audiences.count == 1 || claims["azp"] as? String == clientID else { throw AuthError.invalidIdentity }
        if let nbf = claims["nbf"] as? Double, nbf > now.timeIntervalSince1970 + 5 { throw AuthError.invalidIdentity }
        if let nonce, claims["nonce"] as? String != nonce { throw AuthError.invalidIdentity }
        return VerifiedIdentity(issuer: "https://auth.openai.com", subject: sub, email: claims["email"] as? String)
    }
    private static func derInteger(_ data: Data) -> Data {
        var bytes = data
        while bytes.count > 1 && bytes.first == 0 { bytes.removeFirst() }
        if let first = bytes.first, first & 0x80 != 0 { bytes.insert(0, at: 0) }
        return der(0x02, bytes)
    }
    private static func der(_ tag: UInt8, _ content: Data) -> Data {
        var length: [UInt8] = []
        var count = content.count
        if count < 128 { length = [UInt8(count)] }
        else {
            while count > 0 { length.insert(UInt8(count & 255), at: 0); count >>= 8 }
            length.insert(0x80 | UInt8(length.count), at: 0)
        }
        return Data([tag] + length) + content
    }
}
