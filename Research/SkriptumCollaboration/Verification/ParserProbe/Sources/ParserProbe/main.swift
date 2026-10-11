import Foundation
import Automerge
// Run ONLY as a child of run_probe.py, with bounded synthetic fixtures.
guard CommandLine.arguments.count == 2 else { exit(64) }
let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
print("inputBytes=\(input.count)")
fflush(stdout)
do {
    let document = try Document(input)
    print("decoded heads=\(document.heads().count)")
} catch {
    print("rejected \(error)")
}
