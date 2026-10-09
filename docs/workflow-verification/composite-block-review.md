# Independent composite block fallback review

Verdict: **PASS for inspected preservation/formatting changes**, with native composite editing QA remaining.

Official pinned Markdown AST detects multiple top-level sections within one stored block. Conservative list/quote continuation detection falls back to complete raw source when specialized per-line projection would be unsafe. Raw projection publishes the original String verbatim, no synthetic prefix/suffix, and clamps source/body selections in the same UTF-16 coordinate system. Replacing raw text returns the supplied source directly; existing BlockEditing replacement retains the targeted UUID and does not split/merge the stored block. Existing stored-block initialization still preserves supplied identity and bytes. No normalization or media-path rewrite introduced.

The fallback can select raw mode for some valid simple-looking container forms (such as nonstandard spacing/tab markers). This favors source preservation; it is not a data-loss defect. Official AST parsing and the existing code/list/quote specialized no-op behavior are covered by targeted composite/ordinary regression cases including CRLF, Unicode and fences.

Line-style formatting now uses the actual selected raw-source range only in fallback mode; ordinary projected rows retain their previous full visible-body mapping. MarkdownLineStyling still validates ranges and protects fenced code, and the tests demonstrate a selected body line can be styled without changing surrounding heading/code bytes. Existing first-responder/IME/command-ID guards and persistence-return gates precede native mutation. The raw row label accurately exposes source fallback; no HTML execution or external URL action added.

Tests exercise UUID retention, byte-exact no-op/change, UTF-16 mapping and code rejection. Root reports targeted 20 tests green; SDK compilation and actual native selection/edit/undo remain separate evidence. No additional reproducible blocking defect identified in the diff. No production source changes, Xcode or device actions performed during review.
