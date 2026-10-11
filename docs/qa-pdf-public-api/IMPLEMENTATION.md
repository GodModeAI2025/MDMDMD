# Public semantic PDF export service

ExportEngine.renderSemanticPDF now accepts the same Sendable ExportInput/profile model used by other exports and returns ExportArtifact (PDF data/extension/media type/parser warnings). It runs parsing and worker-local CoreText/Quartz rendering through the existing cancellation-forwarding ExportWorker. Input theme overrides the selected profile; otherwise profile presets apply. Structural tagging is explicit opt-in/default false. Missing attachments and unsupported content errors propagate without a hidden backend fallback.

Evidence:94export tests passed. New tests import SkriptumExport publicly without testable access, generate an actual Letter PDF despite manuscript profile, verify612×792pt paper/title/author/Unicode/list content and artifact fields, preserve raw-HTML warnings, establish pre-cancellation priority over invalid input metadata, and propagate the missing-attachment error. These are public service contracts, not app UI/device acceptance.

Direct unsigned Xcode simulator compilation passed, arm64/x86_64, terminal exit0/BUILD SUCCEEDED (work/pdf-public-api-xcode.log).

The document-based SwiftUI skill was consulted for the export boundary. No new Document/FileDocument editing implementation or file writes were introduced; this is a read-only data export API, so source-document undo registration is unaffected.

Open: manuscript/chapter service integration, debug/native preview/export wiring and full mixed/profile/resource/accessibility/native acceptance. App preview/export still use PaginatedPDF/WebKit. Current Xcode MCP status was freshly read: new proxy agent and project folder approvals remain pending, with no open workspace. No grant was automated or duplicated. Current-source signing and CloudKit gates remain as recorded in the release audit; no upload occurred.
