# Native cloud activation and library binding

Status: implementation plan, 2026-10-09. Identity HTTP and Keychain work is in progress. No live Apple account, deployed service or cloud-library enrollment is proven.

## Activation path

The native library inspector offers cloud connection only for a verified deployment configuration. The first screen identifies the server/operator and explains account purpose. Apple authorization creates a server account only. A separate library action requests sharing/upload and confirms the actual remote library identifier and server readback before storing its binding. Offline writing, exports and eligible device PCC remain usable without this account.

The login path obtains a fresh challenge from its configured HTTPS origin, passes the exact nonce and state to AuthenticationServices, validates returned state and sends bounded proof back to that same origin. It never uses an AI-provider credential as a server credential. Cancellation or failed exchange leaves no cloud binding. A successful exchange supplies internal account/session IDs, expiry and an opaque session token; only the token is secret, and only the device-only Keychain stores it.

## Durable binding

`WritingLibrary.libraryIdentity` is a new random runtime UUID on each instance. It MUST NOT identify a durable local library or select cloud credentials after restart. `ownedWindowLocator()` supplies the existing validated `OwnedLibraryLocator`; this durable local scope selects an explicit record containing server origin, immutable identity profile, internal account UUID and remote library UUID. Page addresses additionally carry remote Space/page UUIDs. No page UUID alone, email, app-default account or other open scene may resolve a cloud scope.

Persist bounded, versioned non-secret binding metadata under the library's owned support scope using the established atomic storage mechanism. Validate canonical origin/profile/UUIDs and matching locator before use. A missing, malformed or unavailable binding disables cloud operations and preserves local content. Changing server or account requires an explicit new connection action; never overwrite an existing remote mapping silently. No session token, Apple proof, refresh grant or private key enters this metadata, preferences, exported document or log.

Each scene obtains its connection from its own library locator. Same-library scenes may share the same explicitly scoped connection actor; different libraries/accounts/origins remain isolated. Closing a scene cancels its UI request without discarding another scene's drafts or credential. A library switch cancels obsolete UI delivery and validates scope again before accepting a response.

## Session and account lifecycle

Absolute session expiry is enforced locally for UX and freshly on the server for authority. GET /session does not renew. On 401/expiry, cloud actions ask for fresh interactive proof; local drafts and revision history remain available. Keychain failures are distinct from a missing credential and cannot trigger an inferred account fallback.

Logout invalidates the connection actor before any suspension and removes the exact Keychain item. Remote confirmation and unknown remote revocation are distinct outcomes. Scheduled tasks and provider grants have independent lifecycle controls; the logout screen explains those controls. Logout-all invalidates every locally cached connection for the same explicit origin/profile/account before the first suspension, blocks new admission and removes all exact scoped Keychain items. It then attempts server revocation using the captured credential and reports confirmed or unknown remote outcome. Failure never restores a connection or token; unrelated accounts and origins remain intact. Apple credential-state loss clears local access and attempts the documented account-wide revocation, reporting uncertainty honestly.

Account deletion is reachable from account settings before login ships. It requires fresh account-bound proof and the server's retention confirmation. Tombstoning, provider revocation and retained collaborative data are explained separately. The app never silently deletes offline libraries or another collaborator's content. Reauthentication receipts remain bounded in memory, expire after five minutes and are never restored as credentials.

## Implementation order and acceptance

1. Freeze/review identity wire DTOs and real HTTP/PostgreSQL proof. Extend the bounded Swift transport for challenge, enrollment, current session, logout-all and deletion without changing strict parsing or redirect denial. Signed issuer notifications remain server-only.
2. Review the concrete profile-scoped Keychain store with actual Security operations and iOS SDK compilation. Register the module in XcodeGen and Swift package configuration, then compile the real app.
3. Implement the durable binding repository and connection registry. Test restart and two-scene isolation with identical page UUIDs in distinct local/remote libraries, malformed metadata, expired credentials and response delivery after switching libraries.
4. Implement native AuthenticationServices and account settings only against a provisioned immutable deployment profile. Verify cancellation, exact nonce/state, Apple authorization, local/remote logout, expiry and account deletion on an eligible device. Enabling capability or registering a production endpoint requires concrete provisioned evidence; a synthetic fixture cannot satisfy it.
5. Bind encrypted page reads and CAS writes to explicit local revisions and confirmed remote addresses. Authentication alone grants no library rights. Preserve both versions on conflict; never silently replace a local manuscript with remote content. Shared realtime merge and server task execution retain their separate R08/R09 acceptance gates.

Evidence must distinguish module tests, simulator Security behavior, real Apple authorization, deployed two-account ACL, physical-device behavior and the exact source included in a TestFlight build. Current Build 2 predates these cloud changes.
