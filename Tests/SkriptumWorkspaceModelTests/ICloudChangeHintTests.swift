import Foundation
import Testing
@testable import SkriptumWorkspaceModel

@MainActor struct ICloudChangeHintTests {
    private final class Target: ICloudChangeHintTarget {
        var calls = 0
        func receiveCloudChangeHint() async { calls += 1 }
    }
    @Test func notificationHintsRequireExactContainerScopeAndSharedSubscription() async {
        let registry = ICloudChangeHints()
        let owned = Target(), shared = Target()
        registry.register(owned, scope: .owned); registry.register(shared, scope: .shared)
        #expect(await registry.receive(container: "another.container", scope: .owned, subscription: nil) == 0)
        #expect(await registry.receive(container: nil, scope: .shared, subscription: ICloudChangeHints.sharedSubscriptionID) == 0)
        #expect(await registry.receive(container: ICloudChangeHints.containerIdentifier, scope: .shared, subscription: "another.subscription") == 0)
        #expect(await registry.receive(container: ICloudChangeHints.containerIdentifier, scope: .shared, subscription: nil) == 0)
        #expect(owned.calls == 0 && shared.calls == 0)
        #expect(await registry.receive(container: ICloudChangeHints.containerIdentifier, scope: .owned, subscription: "engine-owned-ID") == 1)
        #expect(owned.calls == 1 && shared.calls == 0)
        #expect(await registry.receive(container: ICloudChangeHints.containerIdentifier, scope: .shared, subscription: ICloudChangeHints.sharedSubscriptionID) == 1)
        #expect(owned.calls == 1 && shared.calls == 1)
    }
    @Test func removedAndDeallocatedSessionsCannotBeWoken() async {
        let registry = ICloudChangeHints()
        let removed = Target()
        let token = registry.register(removed, scope: .shared)
        registry.remove(token)
        weak var observer: Target?
        do { let temporary = Target(); observer = temporary; registry.register(temporary, scope: .shared) }
        #expect(observer == nil)
        #expect(await registry.receive(container: ICloudChangeHints.containerIdentifier, scope: .shared, subscription: ICloudChangeHints.sharedSubscriptionID) == 0)
        #expect(removed.calls == 0)
        // A new registration has an independent token; retiring the old token
        // cannot cancel the new session's same-scope wake-up.
        registry.register(removed, scope: .shared); registry.remove(token)
        #expect(await registry.receive(container: ICloudChangeHints.containerIdentifier, scope: .shared, subscription: ICloudChangeHints.sharedSubscriptionID) == 1)
    }
    @Test func cancelledDeliveryDoesNotStartTargetWork() async {
        let registry = ICloudChangeHints(), target = Target()
        registry.register(target, scope: .owned)
        let delivery = Task { @MainActor in
            await registry.receive(container: ICloudChangeHints.containerIdentifier, scope: .owned, subscription: nil)
        }
        // The MainActor has not yielded, so cancellation precedes dispatch.
        delivery.cancel()
        #expect(await delivery.value == 0)
        #expect(target.calls == 0)
    }
    @Test func malformedPushCannotWakeRegisteredSession() async {
        let registry = ICloudChangeHints(), owned = Target()
        registry.register(owned, scope: .owned)
        #expect(await registry.receive([:]) == 0)
        #expect(await registry.receive(["container": ICloudChangeHints.containerIdentifier, "document": "untrusted"]) == 0)
        #expect(owned.calls == 0)
    }
}
