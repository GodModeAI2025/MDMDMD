# Owned cloud binding storage evidence

Scope: pure Core durable nonsecret metadata only, implementing storage portion of WORKSPACE_NATIVE_BINDING_PLAN. No live account/library connection, Keychain, App, root manifest or Xcode changes.

## API/storage contract

CloudLibraryBinding contains schema1, OwnedLibraryLocator, canonical HTTPS origin, immutable ASCII profile ID1–64UTF8 bytes, internal account UUID and remote library UUID. No token/proof/key/provider type or dependency. Initializer canonicalizes host/default443/trailing root slash; decoded records must already be canonical, supported and valid. Unknown top-level fields rejected. Repository persisted format is sorted-key canonical JSON; byte equality on decode rejects duplicates/unknown nested aliases/trailing content instead of silently dropping them. Maximum file8192bytes checked before and during bounded descriptor read.

Repository maps existing LibraryStoragePaths assistant support namespace to CloudBinding/binding.json. Primary and each importedUUID have separate scopes; no page/runtime UUID selects scope. Reads do not create paths. Every path component is pinned through no-follow directory descriptors; final file opened nonblocking then fstat regular-file checked. Writes use process-global synchronous lock plus compare-current exact record, exclusive0600 temporary file, fsync then same-parent atomic rename. Initial save requires replacing:nil; mapping replacement requires exact previously loaded record. Failed decode never overwrites bytes. remove(expected:) unlinks only matching binding file, leaving siblings and other scopes. Rename is commit point with no subsequent throwable step.

## Test-first evidence

Initial RED work/binding-storage-red.log exit1: missing public APIs (compile-time contract red, not runtime regression claim). First GREEN work/binding-storage-green.log5tests pass. Additional RED work/binding-storage-decode-red.log exit1: one actual failed invalid-decoding expectation;6other tests passed. Final GREEN work/binding-storage-final-green.log exit0:7disk-backed tests in1suite pass.

Command: swift test --build-system native --disable-sandbox --disable-keychain --disable-netrc --scratch-path /private/tmp/SkriptumBindingStorageReview --skip-update --filter CloudLibraryBindingTests. Isolated scratch seeded from already installed local dependency checkouts/repositories; compiler-cache escalation authorized. No network installation performed. Tests cover restart, exact replacementCAS, primary/two imports same account+remote identifiers, remove middle scope with other bindings preserved, missing/malformed/unsupported/wrong-scope/oversized records unchanged, strict origin/profile and decoded validation, duplicate JSON bytes unchanged, no-follow final/ancestor links with outside files untouched, nonregular file rejection, controlled readonly-parent replacement failure preserving existing bytes, scoped sibling preservation.

## Frozen source hashes

41e3160d33556404995bf23ab343bfa8e3de7ac5117466dd87f255851e9ccd84
Sources/SkriptumCore/CloudLibraryBinding.swift 1c6fc1afeff0e13e40b7f1cab1fafc061ce18ca09befdf16890745340fde7290
Tests/SkriptumCoreTests/CloudLibraryBindingTests.swift 6d9484663c6e7e6b1ec01459100d0c4ebdf234db4315471279d003c7206f6953

## Limits / review handoff

Parent independent review and verification: scoped PASS on the exact frozen source/test hashes above. A separate native Swift run using scratch `/private/tmp/SkriptumBindingIndependent` completed exit0 with all7focused tests passing; log `work/binding-storage-independent.log`. Source inspection confirms bounded descriptor reads, no-follow directory traversal, strict decoded validation, explicit process-local CAS, scope-specific removal and secret-free metadata. This confirms the storage component only; no production caller or native cloud activation is claimed. Existing native Swift build-system deprecation warning is recorded and does not change the test result.

Source frozen for root independent review. Process-local serialization matches current single-app scene/store ownership; no cross-process CAS/adversarial replacement race or directory-fsync/power-loss claim. Canonical owned native roots required (system alias paths such as /var rejected, not silently resolved). JSON canonical disk format intentionally rejects externally reformatted documents; this is private versioned metadata, not a user-editable interchange format. Locator copied metadata cannot establish remote authorization; future connection repository must originate records only after explicit authorized remote readback. Native SDK/App resource registration, account/profile Keychain lookup, cloud connection actors, import binding absence, UI/authentication/two-scene delivery and server authority remain subsequent gates. Full R08/R09/product scope remains open.
