# Independent block palette layout review

Verdict: **PASS for the inspected layout/action fix**, with rebuilt native hit-testing still required.

The editor now has a concrete VStack containing the main scroll surface and optional palette as siblings. Its enclosing PageWritingView already allocates the editor above the separate editingBar/status siblings. Consequently palette height participates in ordinary parent layout rather than extending a child safe-area inset into the independently allocated formatting bar. The palette's own bounded scroll region (maximum 260 points) keeps overflow choices scrollable instead of demanding a fixed full content height. No overlay or absolute coordinate placement introduced.

Existing editor onChange/task modifiers attach to the stable outer VStack; toggling the palette changes a child without replacing the task owner. ScrollViewReader still contains both surfaces and continues targeting the main editor's block IDs. No block mutation, selection mapping or command gating logic changed.

The page-reference action closes the palette before invoking its callback, matching existing image/prompt handoff behavior. Callback nil still means the parent owns asynchronous reference selection; synchronous nonnil callback still uses the existing insert route and slash anchor. Buttons retain accessibility identifiers and minimum touch dimensions. Failed persistence may leave the palette closed, but parent prepareNavigation prevents opening the reference sheet or leaving the unsaved editor; reopening remains available.

This source review establishes the allocation correction, not native touch correctness. QA must verify that the advertised Seitenverweis rectangle now receives the tap rather than format-heading, including compact keyboard-present layout. No edits, Xcode or device calls performed during review.
