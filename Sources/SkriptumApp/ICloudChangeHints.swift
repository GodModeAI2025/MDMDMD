import Foundation
import CloudKit

@MainActor protocol ICloudChangeHintTarget: AnyObject, Sendable {
    func receiveCloudChangeHint() async
}

/// A push is only a wake-up hint. It cannot select an account, open a document,
/// grant a share, apply payload contents, or enter any AI executor.
@MainActor final class ICloudChangeHints {
    static let shared = ICloudChangeHints()
    static let containerIdentifier = "iCloud.com.mobilebox.Skriptum"
    static let sharedSubscriptionID = "scriptum.shared-database.v1"
    enum Scope: Sendable { case owned, shared }
    private final class Entry {
        weak var target: (any ICloudChangeHintTarget)?
        let scope: Scope
        init(_ target: any ICloudChangeHintTarget, scope: Scope) { self.target = target; self.scope = scope }
    }
    private var entries: [UUID: Entry] = [:]
    @discardableResult func register(_ target: any ICloudChangeHintTarget, scope: Scope) -> UUID {
        entries = entries.filter { $0.value.target != nil }
        let token = UUID(); entries[token] = Entry(target, scope: scope); return token
    }
    func remove(_ token: UUID?) { if let token { entries.removeValue(forKey: token) } }
    @discardableResult func receive(container: String?, scope: Scope, subscription: String?) async -> Int {
        guard container == Self.containerIdentifier,
              scope != .shared || subscription == Self.sharedSubscriptionID else { return 0 }
        entries = entries.filter { $0.value.target != nil }
        // Recheck membership when each task starts: stopping an account/session
        // while another target awaits cannot wake a retired registration.
        let tokens = entries.filter { $0.value.scope == scope }.map(\.key)
        return await withTaskGroup(of: Int.self) { group in
            for token in tokens {
                group.addTask { [weak self] in await self?.dispatch(token) ?? 0 }
            }
            var count = 0
            for await value in group { count += value }
            return count
        }
    }
    private func dispatch(_ token: UUID) async -> Int {
        guard !Task.isCancelled, let entry = entries[token], let target = entry.target else { return 0 }
        await target.receiveCloudChangeHint()
        return 1
    }
    @discardableResult func receive(_ payload: [AnyHashable: Any]) async -> Int {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: payload) as? CKDatabaseNotification else { return 0 }
        let scope: Scope
        switch notification.databaseScope {
        case .private: scope = .owned
        case .shared: scope = .shared
        default: return 0
        }
        return await receive(container: notification.containerIdentifier, scope: scope, subscription: notification.subscriptionID)
    }
}
