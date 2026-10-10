# CloudKit change hints — 2026-10-10

Private records continue to use CKSyncEngine. The installed iOS 27 SDK's CKSyncEngineConfiguration.h states that a nil subscriptionID discovers/creates a database subscription. No duplicate private subscription is added. The engine remains explicitly synchronized (`automaticallySync = false`).

Shared document activation creates a container-wide CKDatabaseSubscription named `scriptum.shared-database.v1` with content-available delivery. Subscription save is fenced by the existing exact account and current-generation checks before and after the request. Its failure leaves the session failed rather than claiming automatic delivery; a subsequent explicit synchronization retries registration. No alert, badge, sound, query predicate, public database, or AI task is configured.

The application delegate registers for remote notifications only behind the existing ScriptumICloudProvisioned gate. The async remote-notification handler decodes a CKDatabaseNotification, admits only iCloud.com.mobilebox.Skriptum and private/shared scopes, and requires the exact shared subscription ID for shared hints. Query, record-zone, public, other-container, malformed, and unrelated shared-subscription payloads are not routed. Payload content is never applied as document data.

The registry holds targets weakly and registrations have independent UUIDs. Only activated sessions register; stop removes the registration and clears pending hints. Targets fetch through their existing account/grant-validated transport and durable merge paths. MainActor dispatch rechecks membership and cancellation. Multiple sessions are refreshed concurrently, avoiding serial delay behind one network operation. Each session coalesces hints while busy; a successful synchronization/share/owner-conflict operation drains one pending hint under the original generation fence. Failed operations retain their ordinary explicit recovery path; hints do not turn a failed owner transport into a new activation.

The handler returns noData because delivery alone is not evidence that new records were applied. No owned/shared session is opened on cold start by a push; normal opening still fetches current state. iOS may delay or omit silent notifications, so manual refresh remains necessary. This does not provide guaranteed background polling, timed execution, or collaborative CRDT semantics.

## Provisioning boundary

The source gate remains absent/false, so current builds do not register for push or activate CloudKit. UIBackgroundModes now declares remote-notification alongside processing. No portal capability, CloudKit container, production schema, profile, or aps-environment entitlement was changed. Before enabling the gate, the approved CloudKit/Push capability and matching signed APS entitlement/profile must be established and the real schema verified. Actual APNs receipt, account-switch/revocation races during network requests, and two-device collaboration remain unverified. The existing pending action-time capability approval is not bypassed.

## Verification

Four new routing/lifecycle/cancellation tests check exact container/database/subscription admission, weak ownership, retired-token isolation, malformed payload rejection, and cancellation before target work. Existing unprovisioned owner/shared tests now invoke the hint entry point and still verify no cloud state or document changes. These tests do not simulate Apple subscription save or prove APNs delivery. Build/test receipts are saved alongside this document.

Primary API evidence: installed Xcode iPhoneOS27.0 SDK CloudKit headers CKSyncEngineConfiguration.h, CKSyncEngine.h, CKSubscription.h (database subscriptions support private/shared databases), CKNotification.h (notification payloads are hints), and UIKit UIApplication delegate async notification signature. No third-party dependency was introduced.
