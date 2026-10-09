# Native account foundation checkpoint

This is a component checkpoint under the reviewed account coordinator plan. It does not activate sign-in, select a default account, upload documents, or satisfy native/cloud account lifecycle acceptance.

- Administrator-injected immutable deployment configuration validates exact HTTPS origin, profile/consent identifiers, bounded operator disclosure and HTTPS privacy/service links. No endpoint fallback or environment discovery.
- Account scope distinguishes exact origin, profile and account. Controlled presentation states carry no credentials, Apple proofs or deletion receipts; diagnostic descriptions omit account/session identifiers.
- `WritingLibrary.cloudBindingRepository()` derives its repository from that facade’s actual private document/support roots and owned locator. It does not reconstruct ownership from page IDs or accept user paths.

Permanent test-first evidence: four deployment/scope/redaction tests failed with missing API symbols (`work/workspace-deployment-red.log`), then passed in the root package (`work/workspace-deployment-green.log`). The facade test failed with the missing factory (`work/cloud-binding-facade-red-native.log`), then passed (`work/cloud-binding-facade-green.log`). One Swift Testing macro syntax repair added `try` to the same locator equality assertion; the requirement was unchanged. Initial sandbox compiler-cache failures are separate infrastructure observations, not requirement RED evidence.

The facade test creates two actual `WritingLibrary` stores, saves/removes exact owned binding metadata outside the document directory, proves sibling binding isolation, and compares original library JSON bytes after both operations. This proves component behavior under canonical `/private/tmp` test roots only.

A bounded Xcode MCP container-root probe returned no native execution evidence. The final bridge record did not confirm acceptance of the snippet request; it is a delivery/bridge observation, not proof of a native build timeout or failure. No native path, binding roundtrip or scratch cleanup is claimed. System-root alias canonicalization is unchanged pending actual Foundation-container evidence. Physical path, actual Security admission, Apple authorization, deployment/vault and full account UI remain open.
