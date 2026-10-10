import SwiftUI
import UIKit
import CloudKit
#if canImport(SkriptumCore)
import SkriptumCore
#endif

struct OwnerSharePresentation: Identifiable {
    let scope: ICloudShareScope
    var id: ICloudSyncRecordID {
        switch scope { case .page(let id): .init(kind: .page, id: id); case .space(let id): .init(kind: .space, id: id) }
    }
}
private struct NativeOwnerShare: Identifiable { let id = UUID(); let share: CKShare }

struct ICloudOwnerShareSheet: View {
    let presentation: OwnerSharePresentation
    let library: WritingLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var session: ICloudLibrarySession
    @State private var native: NativeOwnerShare?
    @State private var working = false
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    init(presentation: OwnerSharePresentation, library: WritingLibrary) {
        self.presentation = presentation; self.library = library
        let session = library.iCloudSession ?? ICloudLibrarySession(library: library)
        library.iCloudSession = session; _session = State(initialValue: session)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Zusammenarbeit") {
                    Label(presentation.id.kind == .space ? "Space über iCloud teilen" : "Seite über iCloud teilen", systemImage: "person.2")
                    Text("Die Freigabe umfasst den gewählten Inhalt, seine Unterseiten, Kommentare, Versionen und Bilder. Im nächsten Dialog wählst du Personen und legst fest, ob sie lesen oder bearbeiten dürfen.")
                }
                Section {
                    if session.status == .notConfigured {
                        Label("iCloud-Freigaben noch nicht verfügbar", systemImage: "icloud.slash")
                        Text("Die iCloud-Einrichtung dieser App ist noch nicht abgeschlossen.")
                    } else {
                        if working { ProgressView("Freigabe wird vorbereitet …") }
                        Button("Personen einladen", systemImage: "person.badge.plus", action: prepare)
                            .disabled(working || session.status == .checking || session.status == .syncing)
                        Text("Deine Änderungen werden vor dem Teilen synchronisiert. Der Freigabedialog zeigt die tatsächlich verfügbaren Optionen.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }
            }.scrollContentBackground(.hidden).background { PaperSurface().ignoresSafeArea() }
            .navigationTitle("iCloud-Freigabe")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { task?.cancel(); dismiss() } } }
            .sheet(item: $native) { item in
                NativeCloudSharingController(share: item.share, title: title, failure: { error = "Die Freigabe konnte nicht gespeichert werden. Bitte prüfe die Verbindung und versuche es erneut." })
                    .onDisappear { Task { await session.synchronize() } }
            }
            .onDisappear { task?.cancel() }
        }
    }
    private var title: String {
        switch presentation.scope {
        case .page(let id): library.currentPage(id)?.title ?? "Geteilte Seite"
        case .space(let id): library.spaces.first(where: { $0.id == id })?.title ?? "Geteilter Space"
        }
    }
    private func prepare() {
        guard !working else { return }; working = true; error = nil
        task = Task { @MainActor in
            defer { working = false }
            do {
                if session.status == .failed || session.status == .accountChanged { await session.stop(rememberDisconnect: false) }
                if session.status == .inactive { await session.activate() }
                let share = try await session.createShare(scope: presentation.scope)
                try Task.checkCancellation(); native = NativeOwnerShare(share: share)
            } catch is CancellationError { }
            catch ICloudShareOwnerError.changedManifest {
                error = "Der Inhalt dieser Freigabe hat sich geändert. Bitte kläre die ausstehenden Änderungen, bevor du erneut Personen einlädst."
            } catch ICloudSharePreparationError.overlappingHierarchy {
                error = "Dieser Inhalt gehört bereits zu einer Freigabe. Eine überlappende Freigabe kann nicht erstellt werden."
            } catch {
                self.error = "Die Freigabe ist noch nicht bereit. Prüfe dein iCloud-Konto und synchronisiere die ausstehenden Änderungen. Deine Texte bleiben erhalten."
            }
        }
    }
}

private struct NativeCloudSharingController: UIViewControllerRepresentable {
    let share: CKShare
    let title: String
    let failure: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(title: title, failure: failure) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: CKContainer(identifier: "iCloud.com.mobilebox.Skriptum"))
        controller.availablePermissions = [.allowPrivate, .allowReadOnly, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UICloudSharingController, context: Context) { }
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let title: String
        let failure: () -> Void
        init(title: String, failure: @escaping () -> Void) { self.title = title; self.failure = failure }
        func itemTitle(for csc: UICloudSharingController) -> String? { title }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) { failure() }
    }
}
