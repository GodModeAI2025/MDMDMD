import Foundation
import Testing
@testable import SkriptumCore

@Test @MainActor func iCloudObserverReceivesDiskBaselineInsteadOfOpenDraft() throws {
    let root = URL(fileURLWithPath: "/private/tmp/ICloudObservation-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LibraryStore(directory: root)
    let space = try store.createSpace(title: "Writing")
    let page = try store.createPage(spaceID: space.id, title: "Page", markdown: "Saved")
    let token = try store.beginEditing(pageID: page.id, baseRevision: page.revision)
    try store.updateEditing(token, markdown: "Private unfinished draft")
    var observations: [LibrarySnapshot] = []
    store.onDurableChange = { observations.append($0) }
    _ = try store.createSpace(title: "Other")
    #expect(observations.count == 1)
    #expect(observations[0].pages.first?.markdown == "Saved")
    let persisted = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: root.appendingPathComponent("library.json")))
    #expect(observations[0] == persisted)
    try store.finishEditing(token)
    #expect(observations.count == 2)
    #expect(observations[1].pages.first?.markdown == "Private unfinished draft")
}
