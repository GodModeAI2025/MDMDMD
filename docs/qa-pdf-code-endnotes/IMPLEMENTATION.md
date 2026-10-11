# Code-first endnote admission

A reproduced semantic PDF defect left a code-first endnote's number on the preceding page while its body moved; the actual reference annotation targeted a page without its note text. Endnote admission now measures a leading code block using its code font, unchanged contents and the actual18pt body indent, then reserves the number, spacing and first three code lines together using the existing paragraph planner. Paragraph-first notes retain their current behavior.

The pre-fix real PDF regression failed two page/destination assertions. Final99export tests pass, including public single/manuscript rendering and existing other-format tests. Final unsigned generic iOS Simulator Debug app build succeeds (terminal0/BUILD SUCCEEDED).

Strict independent pypdf inspection of the actual output finds two A4 pages, one reference annotation pointing at page2, and both number and note code on that page. All10foxes and10literal `[^literal]` strings are preserved; no warnings. Poppler rasters of both pages were inspected: reference on page1, number and unclipped code together on page2. This is engine/reader evidence, not actual native app export proof.

Xcode-MCP BuildProject against workspace-hIGciKtoiq returned MCP timeout with no automatic retry, after the caller's actual terminal result. No successful MCP build/install/session/device proof is claimed. No proxy restart or provisioning mutation occurred.

Limits remain: image/table/quote-first endnote admission, mixed content/oversized heading policies, PDF accessibility, all-theme/native/Files acceptance and provider/collaboration requirements. The semantic app path remains Debug QA opt-in; Release retains WebKit. No signed archive/upload/new TestFlight delivery. R01-R15remain binding and open according to the acceptance matrix.

Fresh unsigned iOS27Release compilation also succeeded with terminal0/BUILD SUCCEEDED (work/pdf-code-note-release.log). RELEASE_COMPILE.json records the final executable size/hash, bundle/version/build. This refresh supersedes the earlier unsigned compilation snapshot only; it proves compilation, not signed archive, upload, processing or installation.
