# R15 workflow wave: page links and navigation

The staged read-only Markdown index is integrated into Core with the existing official parser. UI reads one explicit library/Space snapshot, computes index off the main actor, and shows outgoing links/backlinks, unresolved reasons and heading-link insertion. Stable page UUIDs survive title edits. Heading text anchors remain text anchors with documented rename limitations; do not claim persistent heading identities.

Navigation is window/library-local, bounded, back/forward-capable, and resets on library switch. Links to trash, missing pages, unreadable Spaces or malformed internal URLs fail with an explicit message rather than opening another library or forwarding a malformed internal scheme to the OS. Before page navigation, the current editing session must finish successfully; failed persistence blocks navigation. Heading jumps use validated original UTF8 source positions mapped to UIKit UTF16 and check current revision.

Root owns App integration and link UI. Core agent owns only new PageLinks/PageNavigation files and their tests, reusing staged tests; no App or manifests. Fresh reviewer and delegated Xcode-MCP native QA follow frozen source/SDK/tests. R01-R15/R08-R09/provider/release gates remain active.

Core PagePurpose persists writing/material/template with legacy nil=writing. Template creation reuses atomic recovered-page creation, preserves media/metadata and assigns fresh page/block identities. Native manuscript selection/preparation revalidates writing-purpose, and aggregate UI counts exclude research/templates/trash. Core tests supply the actual counter contract.
