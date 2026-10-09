import SwiftUI
import AuthenticationServices
#if canImport(SkriptumCore)
import SkriptumCore
#endif
#if canImport(SkriptumWorkspaceClient)
import SkriptumWorkspaceClient
#endif

struct WorkspaceAccountInspector: View {
    let runtime: WorkspaceAccountRuntime
    let presentation: WorkspaceAccountPresentation
    let windowID: UUID
    let locator: OwnedLibraryLocator
    let expectedFacadeID: UUID
    let libraryTitle: String
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledged = false
    @State private var confirmAll = false
    @State private var confirmDeletion = false
    @State private var localMessage: LocalizedStringResource?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    WorkspaceAccountStatusSection(availability: runtime.availability, state: presentation.state)
                    if let deployment = runtime.deployment {
                        WorkspaceOperatorDisclosureSection(deployment: deployment, acknowledged: $acknowledged, acknowledgementLocked: presentation.isBusy || isActive)
                    }
                    WorkspaceAccountLibrarySection(title: libraryTitle)
                    WorkspaceAccountActionsSection(state: presentation.state, available: runtime.availability == .configured,
                        acknowledged: acknowledged, busy: presentation.isBusy,
                        retryAvailable: presentation.canRetryDeletionLocalCleanup,
                        signIn: signIn, checkExisting: checkExisting, retryLocal: retryLocal, cancel: { runtime.cancel(windowID: windowID, expectedLocator: locator, expectedFacadeID: expectedFacadeID) },
                        logout: { logout(all: false) }, logoutAll: { confirmAll = true }, deletion: { confirmDeletion = true })
                    WorkspaceAccountOutcomeSection(outcome: presentation.operationOutcome, cleanup: presentation.cleanupOutcome)
                    if let localMessage { Text(localMessage).foregroundStyle(Color.primary).accessibilityAddTraits(.isStaticText) }
                }.padding(20).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background { PaperSurface().ignoresSafeArea() }
            .navigationTitle("Konto und Cloud")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() }.disabled(presentation.isBusy) } }
            .interactiveDismissDisabled(presentation.isBusy)
            .task { acknowledged = runtime.isOperatorAcknowledged(windowID: windowID, expectedLocator: locator, expectedFacadeID: expectedFacadeID) }
            .confirmationDialog("Alle Sitzungen abmelden?", isPresented: $confirmAll, titleVisibility: .visible) {
                Button("Alle Sitzungen abmelden", role: .destructive) { logout(all: true) }
                Button("Abbrechen", role: .cancel) {}
            } message: { Text("Alle Sitzungen dieses Kontos werden abgemeldet. Bereits eingerichtete Server-Aufgaben werden dadurch nicht automatisch beendet.") }
            .confirmationDialog("Konto löschen?", isPresented: $confirmDeletion, titleVisibility: .visible) {
                Button("Erneut mit Apple bestätigen", role: .destructive) { deleteAccount() }
                Button("Abbrechen", role: .cancel) {}
            } message: { Text("Ihre lokalen Dokumente bleiben erhalten. Der Dienst behält eigene und geteilte Cloud-Bibliotheken; das Konto und seine Sitzungen werden gesperrt. Bestätigen Sie die Löschung erneut mit demselben Apple-Konto. Eine bereits gesendete Anfrage lässt sich nicht zurücknehmen.") }
        }.tint(Color("AccentColor"))
    }
    private var isActive: Bool { if case .active = presentation.state { return true }; return false }
    private func signIn() {
        guard acknowledged else { localMessage = "Bitte bestätigen Sie zuerst die Hinweise zum Cloud-Dienst."; return }
        do { try runtime.acknowledgeOperator(windowID: windowID, expectedLocator: locator, expectedFacadeID: expectedFacadeID) }
        catch { localMessage = "Diese Bibliothek ist nicht mehr die aktuell geöffnete Bibliothek."; return }
        Task { localMessage = message(await runtime.signIn(windowID: windowID, expectedLocator: locator, expectedFacadeID: expectedFacadeID)) }
    }
    private func checkExisting() {
        guard acknowledged else { localMessage = "Bitte bestätigen Sie zuerst die Hinweise zum Cloud-Dienst."; return }
        do { try runtime.acknowledgeOperator(windowID: windowID, expectedLocator: locator, expectedFacadeID: expectedFacadeID) }
        catch { localMessage = "Diese Bibliothek ist nicht mehr die aktuell geöffnete Bibliothek."; return }
        Task {
            switch await runtime.restore(windowID: windowID, expectedLocator: locator, expectedFacadeID: expectedFacadeID) {
            case .metadataMissing: localMessage = "Für diese lokale Bibliothek ist keine Cloud-Verknüpfung gespeichert."
            case .consentRequired: localMessage = "Bitte bestätigen Sie zuerst die Hinweise zum Cloud-Dienst."
            case .notConfigured, .unavailable: localMessage = "Eine vorhandene Cloud-Sitzung konnte nicht geprüft werden. Ihre lokalen Dokumente bleiben verfügbar."
            case .superseded: localMessage = "Diese Bibliothek ist nicht mehr die aktuell geöffnete Bibliothek."
            case .restorationAttempted: localMessage = nil
            }
        }
    }
    private func retryLocal() {
        Task { localMessage = message(await runtime.retryDeletionLocalCleanup(windowID: windowID, expectedLocator: locator, expectedFacadeID: expectedFacadeID)) }
    }
    private func logout(all: Bool) {
        Task { localMessage = message(await runtime.logout(windowID: windowID, expectedLocator: locator, expectedFacadeID: expectedFacadeID, allSessions: all)) }
    }
    private func deleteAccount() {
        Task {
            guard let result = await runtime.deleteAccount(windowID: windowID, expectedLocator: locator, expectedFacadeID: expectedFacadeID) else {
                localMessage = "Die Kontolöschung ist für diese Bibliothek momentan nicht verfügbar."; return
            }
            switch result {
            case .confirmedAccountTombstone: localMessage = "Die Kontosperre wurde vom Server bestätigt. Ihre lokalen Dokumente bleiben erhalten."
            case .remoteDeletionUnknown: localMessage = "Lokal abgemeldet. Ob der Server die Kontolöschung bestätigt hat, ist unklar."
            case .wrongAccount: localMessage = "Die neue Anmeldung gehört zu einem anderen Konto. Das bisherige Konto wurde nicht gelöscht."
            case .localPersistenceUnavailable: localMessage = "Die lokale Sperre konnte nicht dauerhaft gesichert werden. Cloud-Zugriffe bleiben gesperrt."
            case .authenticationUnavailable: localMessage = "Die erneute Apple-Bestätigung konnte nicht abgeschlossen werden."
            case .cancelled: localMessage = "Die Kontolöschung wurde vor dem Start abgebrochen."
            case .superseded: localMessage = "Dieser Vorgang gehört nicht mehr zum aktuellen Fenster."
            }
        }
    }
    private func message(_ outcome: WorkspaceAccountRuntimeActionOutcome) -> LocalizedStringResource? {
        switch outcome {
        case .completed: nil
        case .consentRequired: "Bitte bestätigen Sie zuerst die Hinweise zum Cloud-Dienst."
        case .presentationUnavailable: "Die Apple-Anmeldung kann in diesem Fenster momentan nicht angezeigt werden."
        case .unavailable: "Die Cloud-Aktion ist momentan nicht verfügbar. Sie können lokal weiterschreiben."
        case .superseded: "Dieser Vorgang gehört nicht mehr zur aktuell geöffneten Bibliothek."
        }
    }
}
private struct WorkspaceAccountStatusSection: View {
    let availability: WorkspaceAccountRuntimeAvailability
    let state: WorkspaceAccountState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "person.crop.circle").font(.title2)
            Text("Schreiben und Export sind auch ohne Cloud-Konto verfügbar.").font(.callout)
        }
    }
    private var title: LocalizedStringResource {
        switch availability {
        case .notConfigured: return "Cloud-Dienst nicht eingerichtet"
        case .configurationUnavailable: return "Cloud-Konfiguration nicht verfügbar"
        case .storageUnavailable: return "Lokale Kontospeicherung nicht verfügbar"
        case .configured: break
        }
        switch state {
        case .active: return "Mit Apple verbunden"
        case .signingIn: return "Apple-Anmeldung läuft"
        case .restoring: return "Sitzung wird geprüft"
        case .signingOut: return "Lokal abgemeldet, Server wird benachrichtigt"
        case .reauthenticatingForDeletion: return "Erneute Apple-Bestätigung läuft"
        case .deleting: return "Kontolöschung wird angefragt"
        case .localDenied: return "Lokal abgemeldet"
        case .unavailable: return "Cloud momentan nicht verfügbar"
        case .signedOut: return "Nicht angemeldet"
        }
    }
}
private struct WorkspaceOperatorDisclosureSection: View {
    let deployment: WorkspaceDeploymentConfiguration
    @Binding var acknowledged: Bool
    let acknowledgementLocked: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ihr Cloud-Dienst").font(.headline)
            LabeledContent("Betreiber", value: deployment.operatorName)
            LabeledContent("Server", value: deployment.origin.url.host ?? "")
            Text(deployment.consentDisclosure)
            Link("Datenschutzhinweise", destination: deployment.privacyURL)
            Link("Informationen zum Dienst", destination: deployment.serviceURL)
            Toggle("Ich habe die Hinweise gelesen und möchte diesen Cloud-Dienst verwenden.", isOn: $acknowledged).disabled(acknowledgementLocked)
            if acknowledgementLocked { Text("Für die aktive Sitzung bleiben die bestätigten Hinweise unverändert. Melden Sie sich ab, um die Cloud-Nutzung zu beenden.").font(.caption) }
            Text("Die Anmeldung verbindet noch keine Bibliothek und lädt keine Dokumente hoch. ChatGPT, API-Schlüssel und Apple Private Cloud Compute bleiben getrennte Einstellungen.").font(.caption)
        }
    }
}
private struct WorkspaceAccountLibrarySection: View {
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diese Bibliothek").font(.headline)
            Text(title)
            Text("Eine Cloud-Bibliotheksverbindung wird hier noch nicht eingerichtet. Ihre lokale Bibliothek bleibt erhalten; eine Anmeldung allein bestätigt keine Synchronisation.").font(.callout)
        }
    }
}
private struct WorkspaceAccountActionsSection: View {
    let state: WorkspaceAccountState
    @Environment(\.colorScheme) private var colorScheme
    let available: Bool; let acknowledged: Bool; let busy: Bool; let retryAvailable: Bool
    let signIn: () -> Void; let checkExisting: () -> Void; let retryLocal: () -> Void; let cancel: () -> Void; let logout: () -> Void; let logoutAll: () -> Void; let deletion: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if busy {
                ProgressView().accessibilityLabel("Cloud-Vorgang läuft")
                Button("Vorgang abbrechen", action: cancel).frame(minHeight: 44)
                if case .deleting = state { Text("Eine bereits gesendete Löschanfrage lässt sich nicht zurücknehmen.").font(.caption) }
            } else if case .active = state {
                Button("Auf diesem Gerät abmelden", action: logout).frame(minHeight: 44)
                Button("Alle Sitzungen abmelden", action: logoutAll).frame(minHeight: 44)
                Button("Konto löschen", role: .destructive, action: deletion).frame(minHeight: 44)
            } else {
                WorkspaceAppleAccountButton(action: signIn).id(colorScheme).frame(height: 50).disabled(!available || !acknowledged)
                Button("Vorhandene Sitzung prüfen", action: checkExisting).frame(minHeight: 44).disabled(!available || !acknowledged)
            }
            if retryAvailable && !busy {
                Button("Lokale Sperre erneut sichern", action: retryLocal).frame(minHeight: 44)
                Text("Diese Aktion wiederholt keine Kontolöschung auf dem Server.").font(.caption)
            }
        }
    }
}
private struct WorkspaceAccountOutcomeSection: View {
    let outcome: WorkspaceAccountOperationOutcome?
    let cleanup: WorkspaceLogoutOutcome?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let outcome {
                switch outcome {
                case .signedIn: Text("Die Anmeldung wurde bestätigt. Ihre Bibliothek wurde dadurch nicht hochgeladen.")
                case .cancelled: Text("Der Vorgang wurde vor dem Start abgebrochen.")
                case .authenticationUnavailable: Text("Die Apple-Bestätigung konnte nicht abgeschlossen werden.")
                case .unavailable(let reason):
                    if reason == .localSignOutPersistenceUnavailable || reason == .localDenialUnavailable { Text("Die lokale Sperre konnte nicht dauerhaft gesichert werden. Cloud-Zugriffe bleiben gesperrt.") }
                    else { Text("Cloud momentan nicht verfügbar. Ihre lokalen Dokumente bleiben verfügbar.") }
                case .logout(let result):
                    switch result {
                    case .confirmedRevocation: Text("Die Abmeldung wurde vom Server bestätigt.")
                    case .revocationUnknown: Text("Lokal abgemeldet. Die Abmeldung auf dem Server ist noch nicht bestätigt.")
                    case .confirmedAccountTombstone: Text("Die Kontosperre wurde vom Server bestätigt.")
                    case .deletionUnknown: Text("Die Bestätigung der Kontolöschung auf dem Server ist unklar.")
                    }
                case .deletion(let result):
                    switch result {
                    case .confirmedAccountTombstone: Text("Die Kontosperre wurde bestätigt. Lokale Dokumente und Cloud-Bibliotheken bleiben erhalten.")
                    case .remoteDeletionUnknown: Text("Lokal abgemeldet. Die Bestätigung der Kontolöschung ist unklar.")
                    case .localPersistenceUnavailable: Text("Die lokale Sperre konnte nicht dauerhaft gesichert werden. Cloud-Zugriffe bleiben gesperrt.")
                    case .wrongAccount: Text("Die neue Anmeldung gehört zu einem anderen Konto. Das bisherige Konto wurde nicht gelöscht.")
                    case .authenticationUnavailable: Text("Die erneute Apple-Bestätigung konnte nicht abgeschlossen werden.")
                    case .cancelled: Text("Die Kontolöschung wurde vor dem Start abgebrochen.")
                    case .superseded: Text("Dieser Vorgang gehört nicht mehr zum aktuellen Fenster.")
                    }
                }
            }
            if cleanup == .remoteRevocationUnknown { Text("Eine neu ausgestellte Sitzung konnte auf dem Server noch nicht bestätigt abgemeldet werden.") }
        }.foregroundStyle(Color.primary)
    }
}

private struct WorkspaceAppleAccountButton: UIViewRepresentable {
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .continue, style: colorScheme == .dark ? .white : .black)
        button.isEnabled = isEnabled
        button.addTarget(context.coordinator, action: #selector(Coordinator.pressed), for: .touchUpInside)
        return button
    }
    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) { context.coordinator.action = action; uiView.isEnabled = isEnabled }
    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func pressed() { action() }
    }
}
