import Foundation
import SkriptumCore

@main struct LibraryProcessProof {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        try await MainActor.run {
            let store = try LibraryStore(directory: URL(fileURLWithPath: args[1]))
            func send(_ value: [String: String]) throws {
                let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
                FileHandle.standardOutput.write(data + Data("\n".utf8))
            }
            switch args[0] {
            case "bootstrap":
                let space = try store.createSpace(title: "Baseline")
                _ = try store.createPage(spaceID: space.id, title: "Page", markdown: "Original\r\n")
                try send(["state": "bootstrapped"])
            case "writer":
                try send(["state": "ready"])
                guard readLine() == "GO" else { throw CocoaError(.userCancelled) }
                do {
                    let space = try store.createSpace(title: args[2])
                    try send(["state": "committed", "id": space.id.uuidString])
                } catch LibraryError.revisionConflict { try send(["state": "conflict"])
                }
            case "draft":
                let page = store.snapshot.pages.first!
                let token = try store.beginEditing(pageID: page.id, baseRevision: page.revision)
                let markdown = String(data: try Data(contentsOf: URL(fileURLWithPath: args[2])), encoding: .utf8)!
                try store.updateEditing(token, markdown: markdown)
                try send(["state": "journaled"])
                _ = readLine()
            case "inspect":
                let data = try JSONEncoder().encode(store.snapshot)
                try data.write(to: URL(fileURLWithPath: args[2]), options: .atomic)
                try send(["state": "inspected"])
            default: throw CocoaError(.userCancelled)
            }
        }
    }
}
