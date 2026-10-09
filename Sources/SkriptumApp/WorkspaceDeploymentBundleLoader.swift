import Foundation
import CoreFoundation

enum WorkspaceDeploymentBundleResult: Sendable {
    case notConfigured
    case configured(WorkspaceDeploymentConfiguration)
    case unavailable
}
/// Only explicitly bundled operator configuration; no discovery/env/default URL.
enum WorkspaceDeploymentBundleLoader {
    static func load(bundle: Bundle = .main) -> WorkspaceDeploymentBundleResult { load(infoDictionary: bundle.infoDictionary ?? [:]) }
    static func load(infoDictionary: [String: Any]) -> WorkspaceDeploymentBundleResult {
        guard let supplied = infoDictionary["ScriptumWorkspaceDeployment"] else { return .notConfigured }
        guard let row = supplied as? [String: Any], let flag = row["configured"] as? NSNumber,
              CFGetTypeID(flag) == CFBooleanGetTypeID() else { return .unavailable }
        if !flag.boolValue { return Set(row.keys) == ["configured"] ? .notConfigured : .unavailable }
        let fields = ["origin", "profileID", "consentVersion", "operatorName", "privacyURL", "serviceURL", "consentDisclosure"]
        guard Set(row.keys) == Set(fields + ["configured"]), fields.allSatisfy({ row[$0] is String }) else { return .unavailable }
        guard let value = try? WorkspaceDeploymentConfiguration(origin: row["origin"] as! String, profileID: row["profileID"] as! String,
              consentVersion: row["consentVersion"] as! String, operatorName: row["operatorName"] as! String,
              privacyURL: row["privacyURL"] as! String, serviceURL: row["serviceURL"] as! String,
              consentDisclosure: row["consentDisclosure"] as! String) else { return .unavailable }
        return .configured(value)
    }
}
