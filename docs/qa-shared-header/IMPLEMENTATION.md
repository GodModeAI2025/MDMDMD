# Shared-document header layout

User reference: Bildschirmfoto 2026-10-10 um 10.05.37.heic, preserved as user-reference.png. The reference shows a large white navigation header/vertical gap above the paper surface. Its truncated unavailable message was already corrected in dcfdf4e; this change addresses the header itself.

The shared document sidebar and editor now use the native inline navigation title. Both visible column toolbars explicitly use the adaptive PaperBase color and a visible navigation background. The split container's PaperSurface extends through its safe-area background. This keeps the native status/navigation controls while integrating their surroundings with the established paper palette. Toolbar items, disabled admission, document/draft state, scene lifecycle, and transport behavior are unchanged.

Xcode MCP Build820 passed. The native/ report and screenshots record the actual phone result against these source changes. This is a scoped iPhone layout verification; it does not establish real CloudKit collaboration or a newly distributed TestFlight build. No new model tests were added for this reversible visual change.
