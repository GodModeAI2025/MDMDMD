import SwiftUI
import AppKit
import CloudKit

@main struct SkriptumMacApp: App {
    @NSApplicationDelegateAdaptor(ScriptumMacDelegate.self) private var delegate
    @State private var library: WritingLibrary
    @AppStorage private var appearance: Int
    init() {
        let loaded = Self.makeLibrary()
        _library = State(initialValue: loaded)
        _appearance = AppStorage(wrappedValue: 0, "Scriptum.mac.appearance", store: loaded.preferences)
    }
    private var chosenScheme: ColorScheme? { appearance == 1 ? .light : appearance == 2 ? .dark : nil }
    @MainActor private static func makeLibrary() -> WritingLibrary {
#if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--scriptum-mac-qa-root"), args.indices.contains(index + 1) {
            let root = URL(fileURLWithPath: args[index + 1], isDirectory: true)
            let documents = root.appendingPathComponent("Documents", isDirectory: true)
            let support = root.appendingPathComponent("Support", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let store = try LibraryStore(directory: documents.appendingPathComponent("Skriptum"))
                if store.snapshot.spaces.isEmpty {
                    let space = try store.createSpace(title: "Native Mac QA")
                    _ = try store.createPage(spaceID: space.id, title: "Schreiben auf dem Mac", markdown: "# Schreiben auf dem Mac\n\nEin eigener Satz. Markdown, Tastatur und iCloud gehören zusammen.\n\n## Zweiter Abschnitt\n\nDer Text wächst mit seinem Inhalt.\n")
                }
                guard let preferences = UserDefaults(suiteName: "com.mobilebox.Scriptum.MacQA") else { fatalError("QA preferences unavailable") }
                return try WritingLibrary(store: store, documentRoot: documents, supportRoot: support, preferences: preferences)
            } catch { fatalError("Isolated Mac QA library unavailable: \(error)") }
        }
#endif
        return WritingLibrary()
    }
    var body: some Scene {
        WindowGroup("Scriptum", id: "library") {
            MacWritingWorkspace(library: library).frame(minWidth: 900, minHeight: 560).preferredColorScheme(chosenScheme)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands { MacWritingCommands(); MacEditorMenuCommands() }
        WindowGroup("Geteiltes Dokument", id: "shared-document", for: ICloudSharedStoreIdentity.self) { identity in
            ICloudSharedWindowHost(identity: identity.wrappedValue,
                directory: library.iCloudStorageDirectory().appendingPathComponent("SharedDocuments"))
                .frame(minWidth: 720, minHeight: 480).preferredColorScheme(chosenScheme)
        }
        Settings { MacApplicationSettings(preferences: library.preferences).frame(width: 520, height: 420).preferredColorScheme(chosenScheme) }
    }
}

@MainActor @Observable final class MacShareRouting {
    static let shared = MacShareRouting()
    var pending: ICloudSharedStoreIdentity?
    var failure: String?
    func claim() -> ICloudSharedStoreIdentity? { defer { pending = nil }; return pending }
}

@MainActor final class ScriptumMacDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApplication.shared.registerForRemoteNotifications() }
    func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        let session = ICloudSharedSession(directory: WorkspaceSystemContainerRoots.applicationSupport
            .appendingPathComponent("ICloudSync/SharedDocuments", isDirectory: true))
        Task { @MainActor in
            await session.accept(metadata)
            if let identity = session.identity, session.status == .ready { MacShareRouting.shared.pending = identity }
            else { MacShareRouting.shared.failure = "Die iCloud-Einladung konnte noch nicht geöffnet werden. Deine lokalen Texte bleiben erhalten." }
            session.stop()
        }
    }
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Task { @MainActor in _ = await ICloudChangeHints.shared.receive(userInfo) }
    }
}

@MainActor @Observable final class MacWorkspaceController {
    let library: WritingLibrary
    let navigation = EditorNavigationGuard()
    private var chosenPage: UUID?
    var spaceID: UUID?
    var filter = "Alle Seiten"
    var query = ""
    var importing = false
    var showingICloud = false
    var showingShared = false
    var showingManuscript = false
    var writingFocus = false
    var selectedPage: UUID? {
        get { chosenPage }
        set { if navigation.prepare() { chosenPage = newValue } }
    }
    init(library: WritingLibrary) { self.library = library }
    func toggleWritingFocus() {
        guard chosenPage != nil, navigation.prepare() else { return }
        writingFocus.toggle()
    }
    func newPage() {
        guard navigation.prepare() else { return }
        if library.spaces.isEmpty { spaceID = library.createSpace(title: "Meine Texte") }
        chosenPage = library.createPage(spaceID: spaceID); filter = "Alle Seiten"
    }
    func chooseSpace(_ id: UUID?) { guard navigation.prepare() else { return }; spaceID = id; chosenPage = nil; filter = "Alle Seiten" }
    func imported(_ urls: [URL]) { guard navigation.prepare() else { return }; for url in urls { chosenPage = library.importMarkdown(url: url, spaceID: spaceID) } }
}

extension FocusedValues { @Entry var macWorkspace: MacWorkspaceController? }
struct MacWritingCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.macWorkspace) private var workspace
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Neues Fenster") { openWindow(id: "library") }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Neue Seite") { workspace?.newPage() }.keyboardShortcut("n").disabled(workspace == nil)
            Button("Markdown importieren …") { if workspace?.navigation.prepare() == true { workspace?.importing = true } }.keyboardShortcut("o").disabled(workspace == nil)
        }
        CommandMenu("Bibliothek") {
            Button("iCloud …") { if workspace?.navigation.prepare() == true { workspace?.showingICloud = true } }.disabled(workspace == nil)
            Button("Geteilte Dokumente …") { if workspace?.navigation.prepare() == true { workspace?.showingShared = true } }.disabled(workspace == nil)
            Button("Manuskript zusammenstellen …") { if workspace?.navigation.prepare() == true { workspace?.showingManuscript = true } }.disabled(workspace == nil)
        }
    }
}

struct MacApplicationSettings: View {
    @AppStorage private var appearance: Int
    init(preferences: UserDefaults) {
        _appearance = AppStorage(wrappedValue: 0, "Scriptum.mac.appearance", store: preferences)
    }
    var body: some View {
        TabView {
            Form {
                Section("Scriptum") {
                    Text("Deine Texte bleiben in deiner Bibliothek. iCloud und KI richtest du unabhängig voneinander ein.")
                    Link("Datenschutz", destination: URL(string: "https://www.mobilebox-consulting.de/datenschutzerkl%C3%A4rung-privacy-policy/")!)
                }
                Section("Darstellung") {
                    Picker("Erscheinungsbild", selection: $appearance) {
                        Text("System").tag(0); Text("Hell").tag(1); Text("Dunkel").tag(2)
                    }.pickerStyle(.segmented)
                    Text("Schrift und Schreibbreite kannst du direkt über die Schreibansicht für deinen Space einstellen. Mit „System“ übernimmt die Oberfläche das Erscheinungsbild von macOS.") }
            }.formStyle(.grouped).tabItem { Label("Allgemein", systemImage: "gearshape") }
            MacLicenseList().tabItem { Label("Lizenzen", systemImage: "doc.text") }
        }
    }
}
private struct MacLicenseList: View {
    private struct Entry: Identifiable { let id: String; let text: String }
    @State private var entries: [Entry] = []
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) { ForEach(entries) { Text($0.text).font(.system(.caption, design: .monospaced)).textSelection(.enabled) } }.padding() }
            .task {
                var visited = Set<String>()
                entries = Self.read("Acknowledgements", visited: &visited)
                if entries.isEmpty { entries = [Entry(id: "missing", text: "Lizenzinformationen sind im App-Paket enthalten.")] }
            }
    }
    private static func read(_ file: String, visited: inout Set<String>) -> [Entry] {
        guard visited.insert(file).inserted,
              let url = Bundle.main.url(forResource: file, withExtension: "plist", subdirectory: "Settings.bundle"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let rows = plist["PreferenceSpecifiers"] as? [[String: Any]] else { return [] }
        let strings = plist["StringsTable"] as? String ?? "Root"
        let settings = Bundle.main.url(forResource: "Settings", withExtension: "bundle").flatMap(Bundle.init(url:))
        func localized(_ value: String) -> String {
            settings?.localizedString(forKey: value, value: value, table: strings) ?? value
        }
        return rows.enumerated().flatMap { index, row -> [Entry] in
            if let child = row["File"] as? String { return read(child, visited: &visited) }
            let title = row["Title"] as? String ?? "", body = row["FooterText"] as? String ?? ""
            return title.isEmpty && body.isEmpty ? [] : [Entry(id: file + "." + String(index), text: localized(title) + "\n" + localized(body))]
        }
    }
}
