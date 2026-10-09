# iCloud implementation status

The product uses iCloud, without an operated Scriptum service or separate account. The previous server account runtime is removed from app composition/navigation. Provider credentials and private conversation files remain outside the document sync projection.

Implemented: account/library-scoped durable outbox, stable record projection and page ancestry; preserved divergent page revisions and open-edit protection; committed-snapshot observer; restart-safe projection checkpoint; native CKSyncEngine/CKAsset transport with durable incoming inbox, account fences and exact immutable sent-revision acknowledgement. A metadata-only CloudKit save response does not require an asset to be downloaded again. Incoming content still requires verified asset bytes and rejects conflicting reuse of a revision identifier.

Current full local regression: 58 XCTest plus 246 executed Swift Testing tests passed, 304 executed tests total. One historical own-server integration spec was skipped without opt-in; it is not iCloud evidence. Ten outbox, eight checkpoint, seven local CloudKit inbox/acknowledgement tests and account-replacement binding regressions are included. These tests do not contact the real CloudKit service.

Remaining before sync acceptance: production UI/runtime activation, all incoming metadata/deletion/attachment merges and asset transfer, container and push capability provisioning, production schema, recovery/account-change validation against Apple, and actual two-device synchronization. The Apple portal currently shows iCloud disabled; action-time confirmation is pending. Existing TestFlight build 2 predates these changes. A new signed archive, upload, processing, compliance and internal assignment are still required.

The local iCloud settings screen currently reports setup unfinished. No button or status claims operational synchronization.
