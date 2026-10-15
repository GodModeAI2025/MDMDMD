# CommonMark outline repair — 2026-10-15

Both native inspectors now use the existing CommonMark heading traversal. Code examples and raw HTML no longer become outline entries; Setext, list/quote-nested, indented and formatted headings navigate to their original UTF-16 source positions. Source bytes are never rewritten.

The shared view parses an immutable source snapshot away from the main actor. Row identities stay stable for that snapshot, old results cannot replace a cancelled task, and no stale range is offered while the source changes. The snapshot equality deliberately compares UTF-8 storage, since canonically equivalent Unicode strings can have different UTF-16 positions. The batch coordinate mapper builds one line map for all headings, preserving LF, CRLF and CR terminators.

## Evidence

- Actual behavior RED: `red-local-cache.log`, 4 test definitions / 6 cases, Swift exit 1 and 11 issues against the extracted unchanged scanner. Exact RED projection and test files are preserved here. The initial `red.log` failed on the inaccessible default compiler cache and is explicitly infrastructure-only.
- GREEN: `green.log`, 15 definitions / 17 cases across PageOutlineTests, PageLinksTests and PageNavigationTests, Swift exit 0. The 4 RED definitions remain unchanged; GREEN adds long-manuscript and batch-coordinate boundary regressions.
- Coverage includes fenced/indented/nested code, raw HTML, Setext, nested heading targets, inline formatting, duplicate titles, composed/decomposed Unicode, emoji, all three line endings, invalid coordinates, unchanged source bytes, and 2,000 original heading targets.
- The long-manuscript case completed in 0.032 seconds in this local run. This is a measurement, not a performance guarantee.
- Existing link/scope/slug/backlink and navigation fail-closed tests passed unchanged.
- `git diff --check` returned 0. SOURCE.json binds the reviewed implementation; SHA256SUMS binds retained evidence.

## Boundaries

No app, simulator, device or live CloudKit was started. No project file, version, release or portal was changed here. Native iOS/macOS SDK compilation of the shared SwiftUI section and project registration of PageOutline.swift belong to the parent integration check. No device tests are made mandatory.

The unrelated compiler warning from the concurrently prepared cloud metadata regression is recorded in the original GREEN log; its owning agent was informed before their RED/GREEN run. It does not affect these selected tests.

Separate next product gap, not implemented here: Markdown file import preserves UTF-8 source but does not import referenced relative images. WritingLibrary.importMarkdown currently calls createPage with text only; export assets come solely from page.attachments, so imported `![Photo](images/photo.png)` cannot be previewed/exported with its image. A bounded remedy is an explicit selected-folder/Markdown-package import with atomic attachment collection, safe relative-path validation and a source-preserving alias map. Existing .scriptum library import is not this missing flow.
