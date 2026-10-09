import SwiftUI
import UIKit
#if canImport(SkriptumAuth)
import SkriptumAuth
#endif

/// Captures only the window hosting this view; never searches other scenes.
@MainActor final class WorkspacePresentationAnchors {
    private final class Entry {
        weak var window: UIWindow?
        let readerID: UUID
        init(_ window: UIWindow, readerID: UUID) { self.window = window; self.readerID = readerID }
    }
    private var entries: [UUID: Entry] = [:]
    private final class ReaderOwner {
        weak var view: UIView?
        let id: UUID
        init(view: UIView, id: UUID) { self.view = view; self.id = id }
    }
    private var owners: [UUID: ReaderOwner] = [:]

    func claim(windowID: UUID, readerID: UUID, view: UIView) {
        owners = owners.filter { $0.value.view != nil }
        guard owners[windowID] != nil || owners.count < 64 else { return }
        owners[windowID] = ReaderOwner(view: view, id: readerID)
        entries.removeValue(forKey: windowID)
    }

    func release(windowID: UUID, readerID: UUID) {
        guard owners[windowID]?.id == readerID else { return }
        owners.removeValue(forKey: windowID)
        entries.removeValue(forKey: windowID)
    }

    func update(windowID: UUID, readerID: UUID, window: UIWindow?) {
        guard owners[windowID]?.id == readerID, owners[windowID]?.view != nil else { return }
        entries = entries.filter { $0.value.window != nil }
        guard let window else {
            if entries[windowID]?.readerID == readerID { entries.removeValue(forKey: windowID) }
            return
        }
        guard entries[windowID] != nil || entries.count < 64 else { return }
        entries[windowID] = Entry(window, readerID: readerID)
    }

    func proof(windowID: UUID) throws -> WorkspaceAccountProofAcquisition {
        guard let owner = owners[windowID], owner.view != nil,
              let entry = entries[windowID], entry.readerID == owner.id,
              let window = entry.window,
              let scene = window.windowScene,
              scene.activationState == .foregroundActive else {
            throw WorkspaceAppleAuthorizationError.unavailable
        }
        let authorization = WorkspaceAppleAuthorization(anchor: window)
        return WorkspaceAccountProofAcquisition(
            authorize: { try await authorization.authorize($0) },
            cancel: { authorization.cancel() })
    }
}

struct WorkspacePresentationAnchorReader: UIViewRepresentable {
    let windowID: UUID
    let anchors: WorkspacePresentationAnchors

    final class AnchorView: UIView {
        let readerID = UUID()
        var windowID: UUID?
        var anchors: WorkspacePresentationAnchors?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let windowID { anchors?.update(windowID: windowID, readerID: readerID, window: window) }
        }
    }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.windowID = windowID
        view.anchors = anchors
        anchors.claim(windowID: windowID, readerID: view.readerID, view: view)
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        view.windowID = windowID
        view.anchors = anchors
        anchors.update(windowID: windowID, readerID: view.readerID, window: view.window)
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: ()) {
        if let windowID = view.windowID { view.anchors?.release(windowID: windowID, readerID: view.readerID) }
        view.anchors = nil
    }
}
