import Foundation
import Observation
#if canImport(SkriptumCore)
import SkriptumCore
#endif
#if canImport(SkriptumWorkspaceClient)
import SkriptumWorkspaceClient
#endif

enum WorkspaceLibraryPickerOutcome: Equatable, Sendable {
    case associated, unavailable, superseded, conflict
}

/// Metadata and UI state only. Neither a displayed row nor an association grants access.
@MainActor @Observable final class WorkspaceLibraryPickerPresentation {
    private(set) var rows: [WorkspaceLibraryMetadata] = []
    private(set) var previousCursors: [UUID?] = []
    private(set) var nextAfter: UUID?
    private(set) var association: CloudLibraryBinding?
    private(set) var isBusy = false
    private(set) var outcome: WorkspaceLibraryPickerOutcome?

    func publish(rows: [WorkspaceLibraryMetadata], history: [UUID?], next: UUID?, association: CloudLibraryBinding?, busy: Bool, outcome: WorkspaceLibraryPickerOutcome?) {
        self.rows = rows; previousCursors = history; nextAfter = next
        self.association = association; isBusy = busy; self.outcome = outcome
    }
}
