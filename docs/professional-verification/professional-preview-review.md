# Independent export presentation/preview review

Verdict: **PASS for the inspected UI/data/task fixes**. Native missing-asset export and live-PDF completion remain QA gates.

PageExportPresentation captures the value-type page, its resolved ExportAsset dictionary and the library/Space preference key together into one immutable Identifiable payload. Assignment happens only after finishTyping succeeds and asset resolution succeeds. The item sheet reads that payload directly, instead of presenting from a boolean while reading separately updated states. A thrown asset error prevents presentation. The payload has a new stable UUID for each opening and remains unchanged throughout the sheet session; changing another page/window does not silently replace that export's source or assets. Separate Markdown preview assets remain separate and do not contaminate the export payload.

Both previews now attach .task to a concrete ZStack with stable identity rather than a transparent Group distributed over changing conditional branches. Moving between progress/error/HTML/PDF replaces the child while preserving the task owner. Existing deterministic sorted-key theme hashing and sorted assets supply the semantic task id; successful await paths and generic error paths retain cancellation guards. This directly addresses branch-driven cancellation/restart without disabling legitimate rerendering when export inputs change. Detached HTML work is not explicitly canceled, but its stale result is checked before publication; that existing bounded workload is not a new blocking correctness defect in this change.

Diagnostics log fixed event strings plus booleans (PDF mode, cancellation, renderer retention). They do not include document title, Markdown, asset paths/bytes, hashes, URLs, credentials or provider response content. The logs introduce no mutable shared state. PDF callback and timeout lifecycle otherwise retain the previously reviewed continuation completion logic.

No sources edited and no Xcode/device actions performed. SDK compilation and actual rebuilt-app proof of asset inclusion and completed live PDF are still required before claiming those runtime defects closed.
