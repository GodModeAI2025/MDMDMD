import Foundation
#if canImport(SkriptumWorkspaceClient)
import SkriptumWorkspaceClient
#endif

enum WorkspaceDeploymentError: Error, Equatable, Sendable {
    case invalidOrigin, invalidProfile, invalidDisclosure, invalidDisclosureURL
}

/// Administrator-injected disclosure only; construction performs no network request.
struct WorkspaceDeploymentConfiguration: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let origin: WorkspaceOrigin
    let profileID: String
    let consentVersion: String
    let operatorName: String
    let privacyURL: URL
    let serviceURL: URL
    let consentDisclosure: String

    init(origin: String, profileID: String, consentVersion: String, operatorName: String,
         privacyURL: String, serviceURL: String, consentDisclosure: String) throws {
        guard origin.utf8.count <= 2048, let parsed = try? WorkspaceOrigin(origin) else {
            throw WorkspaceDeploymentError.invalidOrigin
        }
        guard Self.validProfile(profileID), Self.validProfile(consentVersion) else {
            throw WorkspaceDeploymentError.invalidProfile
        }
        guard Self.validText(operatorName, maximum: 256), Self.validText(consentDisclosure, maximum: 4096) else {
            throw WorkspaceDeploymentError.invalidDisclosure
        }
        self.origin = parsed
        self.profileID = profileID
        self.consentVersion = consentVersion
        self.operatorName = operatorName
        self.privacyURL = try Self.disclosureURL(privacyURL)
        self.serviceURL = try Self.disclosureURL(serviceURL)
        self.consentDisclosure = consentDisclosure
    }

    // Exact existing WorkspaceCredential grammar; its helper is module-internal.
    // Keep local validation rather than constructing an unused identity actor.
    static func validProfile(_ value: String) -> Bool {
        (1...128).contains(value.utf8.count) && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0)
        }
    }

    private static func validText(_ value: String, maximum: Int) -> Bool {
        (1...maximum).contains(value.utf8.count)
            && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func disclosureURL(_ value: String) throws -> URL {
        guard (1...2048).contains(value.utf8.count), !value.contains("\\"),
              !value.contains(where: { $0.isWhitespace }),
              let parts = URLComponents(string: value), parts.scheme == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true,
              let url = parts.url else { throw WorkspaceDeploymentError.invalidDisclosureURL }
        return url
    }

    var description: String { "WorkspaceDeploymentConfiguration(<configured>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: ["deployment": "<configured>"]) }
}
