# Private Cloud Compute — 2026-10-08

PCC is a required, independent provider. It needs neither a ChatGPT account nor a third-party API key. No on-device LLM or third-party fallback is allowed when the user selects PCC; manual writing remains available.

- Actual iOS27 SDK PrivateCloudComputeLanguageModel interface inspected and adapter compiled.
- Native capability added with Xcode MCP AddEntitlement to com.mobilebox.Skriptum.
- Real Apple automatic provisioning rejected inclusion of the managed entitlement; a source entitlement alone does not grant access.
- Owner explicitly authorized Developer Portal access and the team-level download-threshold acknowledgment.
- Request submitted for Team SP73Z8JWXM. Apple displayed: Thank you for your submission. It will review the request and contact the owner with status.
- No approval or usable signed PCC profile has yet been verified. Runtime adapter remains gated until signed-profile proof exists.

Official eligibility and request: https://developer.apple.com/private-cloud-compute/
Submission portal: https://developer.apple.com/contact/request/private-cloud-compute/

PCC completion requires approved entitlement, new signed profile readback, compatible physical-device availability, actual inference and quota/error-path testing. This is not substituted with another provider.
