# Private Cloud Compute — 2026-10-08

PCC is a required, independent provider. It needs neither a ChatGPT account nor a third-party API key. No on-device LLM or third-party fallback is allowed when the user selects PCC; manual writing remains available.

- Actual iOS27 SDK PrivateCloudComputeLanguageModel interface inspected and adapter compiled.
- Native capability added with Xcode MCP AddEntitlement to com.mobilebox.Skriptum.
- Real Apple automatic provisioning rejected inclusion of the managed entitlement; a source entitlement alone does not grant access.
- Owner explicitly authorized Developer Portal access and the team-level download-threshold acknowledgment.
- Request submitted for Team SP73Z8JWXM. Apple displayed: Thank you for your submission. It will review the request and contact the owner with status.
- Follow-up: Apple Developer App ID XWHU9VSGJD now offers Access to models on Private Cloud Compute. Enabled it for com.mobilebox.Skriptum, saved, and reloaded the exact App ID from Apple. The checkbox remains checked with Save disabled. Screenshot: pcc-appid-enabled.jpg.
- New real Release archive completed successfully with automatic development provisioning. Readback verifies com.apple.developer.private-cloud-compute=true in both the Apple-signed embedded profile and app code-signature entitlements. Team and application identifier match SP73Z8JWXM.com.mobilebox.Skriptum. Evidence: pcc-profile-proof.json.
- Scriptum now declares a typed boolean ScriptumPCCProvisioned in its generated Info.plist and enables the independent native provider after this verified grant. Other consumers of the AI package retain a disabled default without the flag. Every distributable archive/export must still verify its own distribution profile and signature.
- No physical-device inference, quota behavior or App Store distribution-profile proof has yet been established; availability is checked by the actual FoundationModels PCC model before streaming. There is no fallback.

Official eligibility and request: https://developer.apple.com/private-cloud-compute/
Submission portal: https://developer.apple.com/contact/request/private-cloud-compute/

PCC completion requires approved entitlement, new signed profile readback, compatible physical-device availability, actual inference and quota/error-path testing. This is not substituted with another provider.
