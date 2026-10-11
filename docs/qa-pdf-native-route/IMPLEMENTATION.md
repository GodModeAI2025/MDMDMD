# Native PDF route through the actual app UI

The Debug-only launch argument `--scriptum-semantic-pdf-ui-qa` connects both live PDF preview and actual share export to the public semantic PDF APIs. Both use the same immutable single-page/manuscript snapshot and export profile/theme. Work executes through the existing export worker. Preview checks cancellation before assigning its bytes; export retains the existing cancellation checks, warnings, atomic temporary-file write and share lifecycle.

Release builds and launches without the flag retain the current WebKit renderer. Structural tagging remains default false. This is acceptance wiring, not activation or full PDF accessibility acceptance.

Validation: 97 export tests passed. Final unsigned generic iOS Simulator Debug compilation passed (terminal exit 0, BUILD SUCCEEDED, work/pdf-ui-compile.log). Xcode project was regenerated to include the helper; diff check passed.

Fresh Xcode MCP evidence: project open succeeded for workspace-hIGciKtoiq, scheme Skriptum, destination Arche Rules QA. Agent and exact folder permissions are approved. Subsequent destination list and workspace device-session start returned MCP timeout. The delegated device-interaction review received no session key, installed/launched nothing, and made no device interactions. Its 3307-file source hash comparison found no changes during the freeze. No confirmed session existed to end. Actual preview/scroll, app-generated share PDF, Unicode extraction, short/long fixture fidelity and source readback remain unverified. No restart or automatic retry was used.

CloudKit/Push provisioning and current-source signed archive/TestFlight gates remain open. No release upload occurred. R01-R15 scope remains unchanged.
