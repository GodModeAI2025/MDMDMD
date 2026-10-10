import SwiftUI
import UIKit
import CloudKit

@MainActor final class ScriptumApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        ScriptumBackgroundTaskCoordinator.shared.register()
        return true
    }
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

import BackgroundTasks
import Observation
#if canImport(SkriptumScheduling)
import SkriptumScheduling
#endif

private enum SystemBackgroundRequests {
    @concurrent static func submit(identifier: String, date: Date) async throws {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.earliestBeginDate = date
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try await BGTaskScheduler.shared.submitTaskRequest(request)
    }
    @concurrent static func cancel(identifier: String) async {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
}

/// Registers one application-owned processing identifier at launch. The system
/// supplies the execution window; a document cannot manufacture a BGTask.
@MainActor @Observable final class ScriptumBackgroundTaskCoordinator {
    static let shared = ScriptumBackgroundTaskCoordinator()
    static let identifier = "com.mobilebox.Skriptum.scheduled-processing"
    private let worker = LocalScheduleBackgroundWorker()
    private var registered = false
    private var submittedDate: Date?
    private var updateTask: Task<Void, Never>?
    private var updateAgain = false
    private var running: SystemRun?
    private let requests = BackgroundRequestQueue()
    private var requestGeneration = UUID()
    private(set) var error: String?
    func register() {
        guard !registered else { return }
        registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { task in
            MainActor.assumeIsolated {
                guard let processing = task as? BGProcessingTask else { task.setTaskCompleted(success: false); return }
                Self.shared.handle(processing)
            }
        }
        if !registered { error = "Hintergrundausführung ist derzeit nicht verfügbar. Die Aufgaben bleiben für die geöffnete App erhalten." }
    }
    func submitNext(notBefore: Date? = nil) async {
        guard registered else { return }
        if let notBefore {
            let old = UserDefaults.standard.object(forKey: "Scriptum.backgroundRequestNotBefore") as? Date
            UserDefaults.standard.set(max(old ?? notBefore, notBefore), forKey: "Scriptum.backgroundRequestNotBefore")
        }
        updateAgain = true
        if updateTask == nil {
            // An outgoing scene may be canceled while another scene/activation
            // asks for a new request. The coalesced operation owns its lifetime.
            updateTask = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { updateTask = nil }
                while updateAgain {
                    updateAgain = false
                    await updateRequest()
                }
            }
        }
        await updateTask?.value
    }
    private func updateRequest() async {
        do {
            let targets = try await worker.plan()
            guard let earliest = targets.first?.earliestUTC else {
                let generation = UUID(); requestGeneration = generation; submittedDate = nil
                await requests.perform { [weak self] in
                    await SystemBackgroundRequests.cancel(identifier: Self.identifier)
                    await self?.recordRequest(generation: generation, date: nil, failed: false)
                }
                if requestGeneration == generation {
                    UserDefaults.standard.removeObject(forKey: "Scriptum.backgroundRequestNotBefore")
                }
                return
            }
            let floor = UserDefaults.standard.object(forKey: "Scriptum.backgroundRequestNotBefore") as? Date
            let date = max(earliest, floor ?? .distantPast)
            if submittedDate == date || (submittedDate.map { $0 <= Date() && date <= Date() } ?? false) { return }
            await submitSystemRequest(date: date)
        } catch { self.error = "iOS konnte die Hintergrundprüfung nicht vormerken. Die Aufgabe bleibt für die geöffnete App erhalten." }
    }
    private func handle(_ task: BGProcessingTask) {
        submittedDate = nil
        guard running == nil else { task.setTaskCompleted(success: false); return }
        let run = SystemRun(task)
        running = run
        let cancellation = run.cancellation
        task.expirationHandler = { [weak self, weak run] in
            cancellation.cancel()
            Task { @MainActor in
                guard let run else { return }
                run.finish(success: false)
                if self?.running === run { self?.running = nil }
            }
        }
        let operation = Task { [weak self, run] in
            guard let self else { run.finish(success: false); return }
            var success = false
            // Install expiry before awaiting OS confirmation. A delayed submit
            // must not allow expired work to enter the provider executor.
            await scheduleFallbackRetry()
            do {
                try Task.checkCancellation()
                success = try await worker.run().success && !Task.isCancelled
            }
            catch { success = false }
            // Bound re-admission of blocked/failed work; an earliest date is
            // a request to iOS, not a promise of a timed launch.
            if !Task.isCancelled { await submitNext(notBefore: Date().addingTimeInterval(900)) }
            run.finish(success: success)
            if running === run { running = nil }
        }
        run.cancellation.install(operation)
    }
    private func scheduleFallbackRetry() async {
        let date = Date().addingTimeInterval(900)
        UserDefaults.standard.set(date, forKey: "Scriptum.backgroundRequestNotBefore")
        await submitSystemRequest(date: date)
    }
    private func submitSystemRequest(date: Date) async {
        let generation = UUID(); requestGeneration = generation; submittedDate = nil
        await requests.perform { [weak self] in
            do {
                try await SystemBackgroundRequests.submit(identifier: Self.identifier, date: date)
                await self?.recordRequest(generation: generation, date: date, failed: false)
            } catch {
                await self?.recordRequest(generation: generation, date: nil, failed: true)
            }
        }
    }
    private func recordRequest(generation: UUID, date: Date?, failed: Bool) {
        guard requestGeneration == generation else { return }
        submittedDate = date
        error = failed ? "iOS konnte die Hintergrundprüfung nicht vormerken. Die Aufgabe bleibt für die geöffnete App erhalten." : nil
    }
    private final class SystemRun {
        let task: BGProcessingTask
        let cancellation = LocalBackgroundCancellation()
        private var completed = false
        init(_ task: BGProcessingTask) { self.task = task }
        func finish(success: Bool) {
            guard !completed else { return }; completed = true
            task.expirationHandler = nil
            task.setTaskCompleted(success: success)
        }
    }
}
