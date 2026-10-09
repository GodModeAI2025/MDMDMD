import Foundation
import Darwin
@main struct AdmissionFilesystemProbe {
    static func main() {
        guard CommandLine.arguments.count == 2 else { exit(2) }
        do {
            _ = try WorkspaceCredentialAdmissionContext.shared(denialDirectory: URL(fileURLWithPath: CommandLine.arguments[1]), keychainService: "test.filesystem." + UUID().uuidString)
            print("Unexpected ledger admission"); exit(1)
        } catch WorkspaceCredentialAdmissionError.invalidDenialState { print("Unsafe ledger rejected"); exit(0) }
        catch { print("Unexpected controlled rejection"); exit(2) }
    }
}
