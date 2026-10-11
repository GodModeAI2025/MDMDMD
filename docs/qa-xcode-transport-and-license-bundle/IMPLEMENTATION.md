# Xcode transport diagnosis and release license packaging

The last goal turn made source/test/reader/Release progress (956602c); the overall R01-R15scope remains open. This turn diagnoses the native acceptance transport instead of claiming engine tests prove an installed app.

## Reproduced adapter defect

The owned Python proxy used select(fd) followed by text-mode readline(). A two-line burst reproducibly prefetches the second complete line into Python's buffer while select(fd) reports no readiness. Thus the old loop could ignore a complete reply. This proves a defect in our adapter; it does not prove it caused every prior Xcode timeout.

No client calls were live when the old proxy was gracefully shut down through its own shutdown command; its owning execution session completed with exit0. Only the owned proxy/bridge were renewed, following the reproduced defect, not merely an observation expiry. Xcode itself was not restarted. The repaired proxy uses raw byte reads, explicitly drains complete newline-delimited frames before select, handles partial frames, EOF and notifications/stale IDs, retains bounded framing and records frame metadata. Existing client/socket path is preserved. REPAIRED_PROXY.py is an evidence copy, not a production app dependency.

Tests execute the actual reader functions: coalesced notification/reply, fragmented response, notification/stale-reply filtering and EOF all pass. Official mcpbridge initialize responded. The subsequent real XcodeListWorkspaces call completed with MCP timeout; no actual tool reply frame was recorded beyond initialize. Connection recovery remains unproven.

## Current native Xcode blocker

CUA inspection showed an Xcode access dialog for the OLD owned proxy PID24613, which had already terminated. Existing CLI status had approved the agent/folder, so CLI approval is insufficient to conclude the native dialog disappeared. Attempted dismissal via Don’t Allow was rejected by automatic approval review because it could revoke tool access. No click/state change occurred. A specific user question about dismissing that obsolete request is pending. No workaround, new permission acceptance, simulator install/session or deployment was performed.

## Actual Release Settings.bundle

The current unsigned Release app bundle's Root and Acknowledgements tree resolves all eight panes. Every plist and German/English strings file is byte-identical to the source. The pinned cmark COPYING paragraphs are all present across the BSD/MIT, Houdini, GitHub buffers and utf8proc panes. Foundation Models Utilities and Swift Markdown Apache2.0 LICENSE.txt plus Swift Markdown NOTICE.txt are retained verbatim. See LICENSE_BUNDLE.json. This proves built resource packaging/provenance, not actual iOS Settings navigation/rendering; native UI acceptance remains open.

No signed archive/upload/new TestFlight delivery occurred. CloudKit/Push provisioning and the rest of R01-R15remain separate requirements.
