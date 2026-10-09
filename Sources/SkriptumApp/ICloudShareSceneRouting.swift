import SwiftUI
import UIKit
import CloudKit

@MainActor final class ScriptumApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        guard session.role == .windowApplication else { return session.configuration }
        let configuration = (session.configuration.copy() as? UISceneConfiguration) ?? UISceneConfiguration(name: session.configuration.name, sessionRole: session.role)
        configuration.delegateClass = ScriptumCloudShareSceneDelegate.self
        return configuration
    }
}

/// Uses the scene supplied by UIKit, never a global "first window". Both cold
/// launch metadata and invitations received by an existing scene are handled.
@MainActor final class ScriptumCloudShareSceneDelegate: UIResponder, UIWindowSceneDelegate {
    private var pending: [CKShare.Metadata] = []
    private var controller: UIHostingController<ICloudSharedInvitationView>?
    private var session: ICloudSharedSession?
    private weak var windowScene: UIWindowScene?
    private var presentationTask: Task<Void, Never>?
    func scene(_ scene: UIScene, willConnectTo sceneSession: UISceneSession, options: UIScene.ConnectionOptions) {
        windowScene = scene as? UIWindowScene
        if let metadata = options.cloudKitShareMetadata { enqueue(metadata) }
    }
    func sceneDidBecomeActive(_ scene: UIScene) { schedulePresentation() }
    func sceneDidDisconnect(_ scene: UIScene) { presentationTask?.cancel(); presentationTask = nil; session?.stop(); session = nil; controller = nil; pending = [] }
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        self.windowScene = windowScene; enqueue(metadata)
    }
    private func enqueue(_ metadata: CKShare.Metadata) {
        guard metadata.containerIdentifier == "iCloud.com.mobilebox.Skriptum",
              metadata.hierarchicalRootRecordID != nil,
              !pending.contains(where: { $0.share.recordID == metadata.share.recordID }) else { return }
        pending.append(metadata)
        schedulePresentation()
    }
    private func schedulePresentation() {
        presentationTask?.cancel()
        presentationTask = Task { [weak self] in
            for _ in 0..<30 {
                guard !Task.isCancelled, let self, self.controller == nil, !self.pending.isEmpty else { return }
                self.presentNext()
                if self.controller != nil { return }
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }
    private func presentNext() {
        guard controller == nil, let scene = windowScene, scene.activationState == .foregroundActive,
              let metadata = pending.first,
              let window = scene.windows.first(where: \.isKeyWindow), let root = window.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        guard presenter.viewIfLoaded?.window != nil, !presenter.isBeingDismissed, !presenter.isBeingPresented else { return }
        let directory = WorkspaceSystemContainerRoots.applicationSupport.appendingPathComponent("ICloudSync/SharedDocuments")
        let shared = ICloudSharedSession(directory: directory)
        session = shared
        let content = ICloudSharedInvitationView(session: shared, metadata: metadata) { [weak self] in self?.closeCurrent() }
        let host = UIHostingController(rootView: content)
        host.modalPresentationStyle = .fullScreen
        controller = host
        presenter.present(host, animated: true)
    }
    private func closeCurrent() {
        controller?.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.session?.stop(); self.session = nil; self.controller = nil
            if !self.pending.isEmpty { self.pending.removeFirst() }
            self.schedulePresentation()
        }
    }
}

private struct ICloudSharedInvitationView: View {
    let session: ICloudSharedSession
    let metadata: CKShare.Metadata
    let close: () -> Void
    var body: some View {
        ICloudSharedWritingView(session: session, retry: {
            if session.identity == nil { await session.accept(metadata) }
            else { await session.synchronize() }
        }, close: close)
        .task { await session.accept(metadata) }
    }
}
