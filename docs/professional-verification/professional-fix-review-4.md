# Independent professional fix review 4

Verdict: **PASS for the inspected professional fixes**, with native PDF measurement and SDK/device verification remaining separate release gates.

Reviewed latest QualityCore AST structural signature, official exact Markdown dependency, grammar terminal gate, canceled preview error guards, sorted-key preview task identity, export tab indentation, project registration and PDF layout override. No sources changed.

## Executable independent probes

Compiled current QualityCore against exact pinned existing Markdown/cmark objects (not stale QualityCore objects) and executed 24 probes:

- Nine code-target probes reject: quote indentation and tabs, quote and nested/unclosed fences, list indented/fenced code, Unicode/CRLF positions, inline code and conservative partial-container indentation.
- Three previous nested heading transformations reject: quote, list and nested quote `plain` → `# Title`.
- Nine nested unordered-list/ordered-list/thematic-break transformations reject across those containers.
- Three ordinary `plain` → `ordinary text` corrections still succeed in quote/list/nested quote, with source container preserved.

Fixture and executable are `work/review-probe/`; compile and execution exited 0. These close all reproducible blockers in reviews 1–3. Complete content-neutral AST node kinds/nesting plus heading depth, ordered start, checkbox state, table alignments and code language now participate in before/after comparison; byte-preserving prefix/suffix and protection masks still guard unaffected source.

## Other fixes

Grammar completion/cancel/timeout resolves once under lock and cancels the timer. Old canceled preview failures cannot overwrite newer previews. Sorted JSON keys stabilize theme task identity. Four-column tab accounting prevents indented-code export directives/fences. Generated Xcode project registers the continuation source.

PDF override uses validated theme numbers and controlled insertion before the generated head terminator; resets CSS page/body margins/padding and body width, applies font/paragraph dimensions in CSS pixels for the empirically observed UIKit formatter mapping, and sizes the WebView to the printable rectangle. No static blocking defect identified. This is **not** a claim that 14pt font or 72pt margin measurements have passed: native QA must confirm those values and A4/Letter page geometry on the rebuilt app, as root is doing. SDK compilation also remains root's independent gate.
