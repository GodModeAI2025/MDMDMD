import Foundation

/// Weak, per-library scene registrations. One inactive/closed window cannot
/// revoke another active window, and registrations own neither libraries nor UI.
@MainActor final class ICloudForegroundScenes {
    @MainActor final class Lease {
        fileprivate let id = UUID()
        fileprivate weak var owner: ICloudForegroundScenes?
        fileprivate var active = false
        fileprivate init(owner: ICloudForegroundScenes) { self.owner = owner }
        func update(active: Bool) { self.active = active }
        func close() { active = false; owner?.entries.removeValue(forKey: id); owner = nil }
    }
    private final class Entry {
        weak var lease: Lease?
        init(_ lease: Lease) { self.lease = lease }
    }
    private var entries: [UUID: Entry] = [:]
    var isActive: Bool {
        entries = entries.filter { $0.value.lease != nil }
        return entries.values.contains { $0.lease?.active == true }
    }
    func register() -> Lease {
        entries = entries.filter { $0.value.lease != nil }
        let lease = Lease(owner: self); entries[lease.id] = Entry(lease); return lease
    }
}

@MainActor final class ICloudOwnerForegroundRegistration {
    private weak var library: WritingLibrary?
    private var lease: ICloudForegroundScenes.Lease?
    func update(library: WritingLibrary, active: Bool) {
        if self.library !== library {
            close(); self.library = library; lease = library.iCloudForegroundScenes.register()
        }
        lease?.update(active: active)
        let session = library.iCloudSession ?? ICloudLibrarySession(library: library)
        library.iCloudSession = session
        session.setForegroundActive(library.iCloudForegroundScenes.isActive)
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--scriptum-owner-foreground-ui-qa") {
            print("OWNER_FOREGROUND_QA active=\(active) libraryActive=\(library.iCloudForegroundScenes.isActive) provisioned=\(Bundle.main.object(forInfoDictionaryKey: "ScriptumICloudProvisioned") as? Bool == true)")
        }
#endif
    }
    func close(ifBoundTo expected: WritingLibrary) {
        guard library === expected else { return }
        close()
    }
    private func close() {
        lease?.close(); lease = nil
        library?.iCloudSession?.setForegroundActive(library?.iCloudForegroundScenes.isActive == true)
        library = nil
    }
}
