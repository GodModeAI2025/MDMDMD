# Native manuscript text checking

The native text checker accepts documents up to the existing 8 MiB document budget instead of rejecting sources above 100,000 UTF-8 bytes. Markdown's protected projection is checked in contiguous, whitespace-bounded chunks of at most 16,384 UTF-16 units. Every source byte is retained; oversized unbreakable tokens fail explicitly. A chunk never splits a Swift Character, surrogate pair or combining sequence.

Spelling and asynchronous grammar results are mapped back to absolute source ranges. Existing revision validation, protected Markdown ranges and replace/ignore dialogs remain in use. Cancellation is checked between chunks and spelling results; the dialog displays completed chunks. A grammar rule that spans two chunks may not be detected. Language and grammar support still depend on Apple's installed system services.

The optional user-configured LanguageTool server keeps its existing 100,000-byte input limit. This change does not segment AI requests or establish long-manuscript PCC performance.

Validation: four focused tests passed, covering a manuscript larger than the supplied 579,000-character reference, exact Unicode/CRLF recomposition and range continuity, explicit oversized-token rejection, absolute grammar replacement ranges, and background callback safety. The native iOS Simulator SDK build succeeded. Test receipts: `work/manuscript-quality-tests.log`, `work/manuscript-quality-sdk.log` in the task workspace.

Large-manuscript native runtime performance, memory use on physical devices and grammar findings across chunk boundaries remain unverified.

Xcode MCP simulator regression passed on the normal 54-word welcome page: German native checking, custom server off, progress followed by one spelling hint, correction dialog opened and closed, return to unchanged editor. No AI request, apply/ignore or document modification was performed. Frozen source manifest SHA256: `ad978fd8a50368aba5f35ca800a17dc33432d49208a4d3bfa620e0a12a3631dd`; MCP receipts 53–70, session stopped successfully. This is a small-document UI regression, not a 70,000-word runtime test. Evidence: [completed check](complete.png), [correction dialog](hint.png).
