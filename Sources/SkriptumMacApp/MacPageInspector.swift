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
    private struct Heading: Identifiable { let id: Int; let title: String; let level: Int }
    private var headings: [Heading] {
        var offset = 0
        return page.markdown.components(separatedBy: "\n").compactMap { line in
            defer { offset += line.utf16.count + 1 }
            let level = line.prefix { $0 == "#" }.count
            guard (1...6).contains(level), line.dropFirst(level).first == " " else { return nil }
            return Heading(id: offset, title: String(line.dropFirst(level + 1)), level: level)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Seitenbereich", selection: $section) { Text("Seiteninfo").tag(0); Text("Kommentare & Verlauf").tag(1) }.pickerStyle(.segmented).labelsHidden().fixedSize(horizontal: false, vertical: true).padding()
            if section == 0 {
                Form {
                    Section("Gliederung") {
                        if headings.isEmpty { Text("Überschriften mit # anlegen").foregroundStyle(.secondary) }
                        ForEach(headings) { heading in Button { jump(heading.id) } label: { Text(heading.title).padding(.leading, CGFloat(heading.level - 1) * 10) } }
                    }
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
                }.formStyle(.grouped).scrollContentBackground(.hidden).disabled(library.isReadOnlyRecovery || page.trashed)
            } else {
                PageReviewPanel(page: page, selection: selection, library: library, restored: restored,
                    beforeMutation: beforeMutation, performMutation: performMutation).disabled(library.isReadOnlyRecovery || page.trashed)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background { PaperSurface().ignoresSafeArea() }
    }
}

private struct MacCloudShareButton: NSViewRepresentable {
    let scope: ICloudShareScope
    let library: WritingLibrary
    let beforeMutation: () -> Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSButton { NSButton(title: "Über iCloud teilen …", target: context.coordinator, action: #selector(Coordinator.share(_:))) }
    func updateNSView(_ button: NSButton, context: Context) { context.coordinator.parent = self }
    @MainActor final class Coordinator: NSObject, NSCloudSharingServiceDelegate {
        var parent: MacCloudShareButton
        var service: NSSharingService?
        var task: Task<Void, Never>?
        init(_ parent: MacCloudShareButton) { self.parent = parent }
        @objc func share(_ button: NSButton) {
            guard task == nil, parent.beforeMutation(), let window = button.window else { return }
            let scope = parent.scope, library = parent.library
            button.isEnabled = false
            task = Task { @MainActor [weak self, weak button, weak window] in
                guard let self else { return }
                defer { button?.isEnabled = true; self.task = nil }
                let session = library.iCloudSession ?? ICloudLibrarySession(library: library); library.iCloudSession = session
                do {
                    if session.status == .failed { await session.stop(rememberDisconnect: false) }
                    if session.status == .inactive { await session.activate() }
                    let share = try await session.createShare(scope: scope)
                    guard let button, let window, button.window === window, self.parent.scope == scope else { return }
                    let provider = NSItemProvider(); provider.registerCloudKitShare(share, container: CKContainer(identifier: "iCloud.com.mobilebox.Skriptum"))
                    guard let service = NSSharingService(named: .cloudSharing) else { throw ICloudOwnerPresentationError.notReady }
                    self.service = service; service.delegate = self; service.perform(withItems: [provider])
                } catch { library.saveError = ICloudFailureDiagnostic.describe(error).message }
            }
        }
        nonisolated func options(for service: NSSharingService, share: NSItemProvider) -> NSSharingService.CloudKitOptions { [.allowPrivate, .allowReadOnly, .allowReadWrite] }
        nonisolated func sharingService(_ sharingService: NSSharingService, didSave share: CKShare) { Task { @MainActor [weak self] in await self?.parent.library.iCloudSession?.synchronize() } }
        nonisolated func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
            let diagnostic = ICloudFailureDiagnostic.describe(error)
            Task { @MainActor [weak self] in self?.parent.library.saveError = diagnostic.message }
        }
    }
}
