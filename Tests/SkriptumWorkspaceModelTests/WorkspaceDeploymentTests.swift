import Foundation
import XCTest
@testable import SkriptumWorkspaceModel
import SkriptumWorkspaceClient

final class WorkspaceDeploymentTests: XCTestCase {
    private func configuration(origin: String = "https://Workspace.example:443/", profile: String = "apple-native", consent: String = "v1", operatorName: String = "Operator GmbH", privacy: String = "https://operator.example/privacy", disclosure: String = "Session admission only; library upload requires a separate action.") throws -> WorkspaceDeploymentConfiguration {
        try WorkspaceDeploymentConfiguration(origin: origin, profileID: profile, consentVersion: consent,
            operatorName: operatorName, privacyURL: privacy, serviceURL: "https://operator.example/service", consentDisclosure: disclosure)
    }

    func testExplicitDeploymentCanonicalizesOriginAndRetainsDisclosure() throws {
        let value = try configuration()
        XCTAssertEqual(value.origin.url.absoluteString, "https://workspace.example")
        XCTAssertEqual(value.operatorName, "Operator GmbH")
        XCTAssertEqual(value.privacyURL.absoluteString, "https://operator.example/privacy")
        XCTAssertTrue(value.consentDisclosure.contains("separate action"))
    }

    func testRejectsUnsafeOrMissingDeploymentFields() {
        for origin in ["", "http://workspace.example", "https://user:password@workspace.example", "https://workspace.example/api", "https://workspace.example?token=secret"] {
            XCTAssertThrowsError(try configuration(origin: origin))
        }
        for profile in ["", "apple native", String(repeating: "a", count: 129), "ä"] {
            XCTAssertThrowsError(try configuration(profile: profile))
            XCTAssertThrowsError(try configuration(consent: profile))
        }
        for name in ["", "   ", "Operator\nSecret", String(repeating: "a", count: 257)] {
            XCTAssertThrowsError(try configuration(operatorName: name))
        }
        for url in ["http://operator.example/privacy", "https://user:password@operator.example/privacy", "https://operator.example/privacy?token=secret", "https://operator.example/#secret"] {
            XCTAssertThrowsError(try configuration(privacy: url))
        }
        XCTAssertThrowsError(try configuration(disclosure: String(repeating: "a", count: 4097)))
    }

    func testAccountScopeIsExactAndNoDefaultAccountIsSelected() throws {
        let id = UUID()
        let origin = try WorkspaceOrigin("https://workspace.example")
        let scope = try WorkspaceAccountScope(origin: origin, profileID: "native", accountID: id)
        XCTAssertEqual(scope, try WorkspaceAccountScope(origin: origin, profileID: "native", accountID: id))
        XCTAssertNotEqual(scope, try WorkspaceAccountScope(origin: origin, profileID: "Native", accountID: id))
        XCTAssertNotEqual(scope, try WorkspaceAccountScope(origin: origin, profileID: "native", accountID: UUID()))
        XCTAssertNotEqual(scope, try WorkspaceAccountScope(origin: WorkspaceOrigin("https://other.example"), profileID: "native", accountID: id))
        XCTAssertThrowsError(try WorkspaceAccountScope(origin: WorkspaceOrigin.loopbackForTesting("http://127.0.0.1:1234"), profileID: "native", accountID: id))
    }

    func testDescriptionsOmitDisclosureAndAccountIdentifiers() throws {
        let configuration = try configuration(disclosure: "Private consent text")
        XCTAssertFalse(String(describing: configuration).contains("Private consent text"))
        let scope = try WorkspaceAccountScope(origin: configuration.origin, profileID: configuration.profileID, accountID: UUID())
        let state = WorkspaceAccountState.active(scope: scope, sessionID: UUID(), expiresAt: Date())
        XCTAssertFalse(String(reflecting: state).contains(scope.accountID.uuidString))
        XCTAssertEqual(WorkspaceAccountState.signedOut, .signedOut)
    }
}
