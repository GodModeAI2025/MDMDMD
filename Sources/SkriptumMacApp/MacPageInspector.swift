import SwiftUI
import AppKit
import CloudKit

struct MacPageInspector: View {
    @Binding var page: WritingPage
    let library: WritingLibrary
    let selection: NSRange
    let jump: (Int) -> Void
    let beforeMutation: () -> Bool
    let restored: (WritingPage) -> Void
    let performMutation: PageToolMutation
    @State private var section = 0
    @State private var tag = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacInspectorHeading(title: page.title)
            Picker("Seitenbereich", selection: $section) { Text("Info").tag(0); Text("Kommentare").tag(1); Text("Verlauf").tag(2) }
                .pickerStyle(.segmented).controlSize(.small).labelsHidden()
                .padding(.horizontal, 12).padding(.vertical, 14)
            if section == 0 {
                Form {
                    Section("Seite") {
                        TextField("Seitentitel", text: $page.title, axis: .vertical)
                            .labelsHidden().lineLimit(1...3).accessibilityLabel("Seitentitel")
                    }
                    PageOutlineSection(markdown: page.markdown, jump: jump)
                    Section("Schreibziel") {
                        LabeledContent("Wörter", value: "\(page.markdown.split(whereSeparator: \.isWhitespace).count)")
                        LabeledContent("Zeichen", value: "\(page.markdown.count)")
                        TextField("Wortziel", value: $page.wordGoal, format: .number)
                    }
                    Section("Schlagwörter") {
                        ForEach(page.tags, id: \.self) { value in HStack { Text(value); Spacer(); Button("Entfernen", systemImage: "minus.circle") { page.tags.removeAll { $0 == value } }.labelStyle(.iconOnly) } }
                        TextField("Neues Schlagwort", text: $tag).onSubmit {
                            let value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !value.isEmpty, !page.tags.contains(value) { page.tags.append(value); tag = "" }
                        }
                    }
                    Section("Seitenart") {
                        Picker("Verwendung", selection: $page.purpose) {
                            Text("Schreiben").tag(PagePurpose.writing)
                            Text("Material").tag(PagePurpose.material)
                            Text("Vorlage").tag(PagePurpose.template)
                        }
                    }
                    Section("Zusammenarbeit") {
                        MacCloudShareButton(scope: .page(page.id), library: library, beforeMutation: beforeMutation)
                    }
                }.formStyle(.grouped).controlSize(.small).scrollContentBackground(.hidden).disabled(library.isReadOnlyRecovery || page.trashed)
            } else {
                PageReviewPanel(page: page, selection: selection, library: library, restored: restored,
                    beforeMutation: beforeMutation, performMutation: performMutation, fixedTab: section == 2 ? "Verlauf" : "Kommentare").disabled(library.isReadOnlyRecovery || page.trashed)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct MacInspectorHeading: View {
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Seiteninfo").font(.caption).foregroundStyle(.secondary)
            Text(title.isEmpty ? "Ohne Titel" : title).font(.system(.title3, design: .serif)).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 4)
    }
}

private struct MacCloudShareButton: NSViewRepresentable {
    let scope: ICloudShareScope
    let library: WritingLibrary
    let beforeMutation: () -> Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "iCloud-Freigabe …", target: context.coordinator, action: #selector(Coordinator.share(_:)))
        button.toolTip = "Personen und Zugriffsrechte verwalten. Neue Seiten und Bilder werden einer bestehenden Freigabe nicht automatisch hinzugefügt."
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) { context.coordinator.parent = self }
    @MainActor final class Coordinator: NSObject, NSCloudSharingServiceDelegate {
        var parent: MacCloudShareButton
        var service: NSSharingService?
        var task: Task<Void, Never>?
        private struct Presentation {
            let id: UUID
            let library: WritingLibrary
            let scope: ICloudShareScope
            let session: ICloudLibrarySession
            let connectionRevision: UUID
        }
        private var presentation: Presentation?
        init(_ parent: MacCloudShareButton) { self.parent = parent }
        @objc func share(_ button: NSButton) {
            guard task == nil, parent.beforeMutation(), let window = button.window else { return }
            let scope = parent.scope, library = parent.library
            let operation = library.beginICloudSharePresentation()
            button.isEnabled = false
            task = Task { @MainActor [weak self, weak button, weak window] in
                guard let self else { return }
                defer { button?.isEnabled = true; self.task = nil }
                let session = library.iCloudSession ?? ICloudLibrarySession(library: library); library.iCloudSession = session
                var connectionRevision = session.connectionRevision
                do {
                    if session.status == .failed { await session.stop(rememberDisconnect: false) }
                    if session.status == .inactive { await session.activate() }
                    connectionRevision = session.connectionRevision
                    let share = try await session.createShare(scope: scope)
                    guard let button, let window, button.window === window, self.parent.scope == scope,
                          self.parent.library === library, library.iCloudSession === session,
                          session.connectionRevision == connectionRevision else {
                        library.completeICloudSharePresentation(operation, error: CocoaError(.userCancelled)); return
                    }
                    let provider = NSItemProvider(); provider.registerCloudKitShare(share, container: CKContainer(identifier: "iCloud.com.mobilebox.Skriptum"))
                    guard let service = NSSharingService(named: .cloudSharing) else { throw ICloudOwnerPresentationError.notReady }
                    guard library.confirmICloudSharePresentation(operation) else { return }
                    self.presentation = Presentation(id: operation, library: library, scope: scope, session: session,
                        connectionRevision: connectionRevision)
                    self.service = service; service.delegate = self; service.perform(withItems: [provider])
                } catch {
                    guard self.parent.library === library, self.parent.scope == scope,
                          library.iCloudSession === session, session.connectionRevision == connectionRevision else {
                        library.completeICloudSharePresentation(operation, error: CocoaError(.userCancelled)); return
                    }
                    library.completeICloudSharePresentation(operation, error: error)
                }
            }
        }
        nonisolated func options(for service: NSSharingService, share: NSItemProvider) -> NSSharingService.CloudKitOptions { [.allowPrivate, .allowReadOnly, .allowReadWrite] }
        private func currentPresentation(for serviceID: ObjectIdentifier) -> Presentation? {
            guard let service, ObjectIdentifier(service) == serviceID, let presentation,
                  parent.library === presentation.library, parent.scope == presentation.scope,
                  presentation.library.iCloudSession === presentation.session,
                  presentation.session.connectionRevision == presentation.connectionRevision else { return nil }
            return presentation
        }
        nonisolated func sharingService(_ sharingService: NSSharingService, didSave share: CKShare) {
            let serviceID = ObjectIdentifier(sharingService)
            Task { @MainActor [weak self] in
                guard let presentation = self?.currentPresentation(for: serviceID),
                      presentation.library.confirmICloudSharePresentation(presentation.id) else { return }
                await presentation.session.synchronize()
            }
        }
        // Cloud sharing's dismissal callback distinguishes Done from a failure;
        // implementing it replaces the generic didFailToShareItems callback.
        nonisolated func sharingService(_ sharingService: NSSharingService, didCompleteForItems items: [Any], error: (any Error)?) {
            let serviceID = ObjectIdentifier(sharingService)
            Task { @MainActor [weak self] in
                guard let self, let presentation = self.currentPresentation(for: serviceID) else { return }
                self.service = nil; self.presentation = nil
                guard presentation.library.completeICloudSharePresentation(presentation.id, error: error) else { return }
                if error == nil { await presentation.session.synchronize() }
            }
        }
    }
}
