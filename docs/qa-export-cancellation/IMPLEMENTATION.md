# Cooperative export cancellation

ExportOptionsSheet cancelled its parent Task, but detached Markdown-package and semantic rendering workers did not inherit that cancellation. ExportLivePreview had the same issue when its task was replaced. Parent checks prevented sharing a late result but CPU/memory work continued until completion.

ExportWorker.run now captures a detached worker, forwards parent cancellation through withTaskCancellationHandler, checks cancellation before worker admission and after both operation completion and the parent await. Both export routes and live styled preview use it. The caller continues awaiting worker settlement so a second export is not started while the previous worker is still returning. No detached task is silently abandoned.

Semantic parser checks cancellation on admission, per source line, semantic block and footnote. DOCX rendering checks each block. StoredZIP checks admission, each archive entry, every 65,536 CRC bytes and before final directory assembly. Markdown packaging already checks chapters/AST nodes. No output format or original input is changed.

Cancellation is cooperative, not a hard deadline: a synchronous Swift Markdown parse, HTML render, ImageIO decode, metadata scan, large Data allocation/copy or OS file write can still finish its current step before a checkpoint. No peak-memory or fixed abort latency claim is made. PaginatedPDF retains its existing web-load and per-page cancellation policy. Clipboard blog copy and separate writing preview are outside this change.

Three new deterministic actor-gate tests verify parent cancellation reaches the worker itself, a deliberately uncooperative late result is rejected, a subsequent independent export succeeds, and already-cancelled tasks reject actual ZIP/semantic work. The worker test reads Task.isCancelled inside the operation; it does not infer propagation merely from the parent's throw. Full suite 466 Swift Testing headline (three optional skips) and 58 XCTest pass. Xcode MCP Build939 passes. Native small-fixture regression is recorded separately and does not prove interactive abort timing for huge books. No signing, capability or upload changes.
