#if DEBUG && SWIFT_PACKAGE
import Foundation
import Security

/// Explicit owned-fixture trust, unavailable to shipping app builds.
/// Does not install certificates or change any other transport instance.
public struct WorkspaceVerificationTLSAnchor: Sendable {
    public let origin: WorkspaceOrigin
    private let certificateDER: Data
    private let hostname: String
    private let port: Int

    public init(origin: WorkspaceOrigin, certificateDER: Data) throws {
        guard let components = URLComponents(url: origin.url, resolvingAgainstBaseURL: false),
              components.scheme == "https", let host = components.host,
              ["127.0.0.1", "localhost", "[::1]", "::1"].contains(host),
              let port = components.port, (1...65535).contains(port),
              (1...65536).contains(certificateDER.count),
              SecCertificateCreateWithData(nil, certificateDER as CFData) != nil else {
            throw WorkspaceClientError.invalidConfiguration
        }
        self.origin = origin
        self.certificateDER = certificateDER
        hostname = host.hasPrefix("[") ? String(host.dropFirst().dropLast()) : host
        self.port = port
    }

    func permits(_ url: URL?) -> Bool {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host == URLComponents(url: origin.url, resolvingAgainstBaseURL: false)?.host,
              components.port == port, components.user == nil, components.password == nil else { return false }
        return true
    }

    func accepts(_ challenge: URLAuthenticationChallenge, requestURL: URL?) -> Bool {
        let space = challenge.protectionSpace
        guard permits(requestURL), space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              space.protocol == "https", space.port == port,
              space.host == hostname || (hostname == "::1" && space.host == "[::1]"),
              let trust = space.serverTrust,
              let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData),
              SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, hostname as CFString)) == errSecSuccess,
              SecTrustSetAnchorCertificates(trust, [certificate] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess else { return false }
        return SecTrustEvaluateWithError(trust, nil)
    }
}
#endif
