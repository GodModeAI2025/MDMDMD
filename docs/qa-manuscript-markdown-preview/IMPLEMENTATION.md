# Manuscript Markdown source preview

ManuscriptExportSheet intentionally supplies an empty synthetic page source and independent ExportInput chapters. The raw Markdown ZIP preview incorrectly read that empty page, showing a blank preview for a nonempty manuscript.

ExportMarkdownSourcePreview now captures the immutable export input snapshot, assigns stable per-chapter identifiers for this presentation, and exposes an ordered chapter picker. It displays each chapter original Markdown separately, including its own reference/footnote definitions, Unicode and unfinished code fences; no combined Markdown is synthesized. Switching chapter resets the source scroll viewport. The title row and explanatory note are separate from source text. Single-page preview still reads the page source. Export bytes, renderer and originals are unchanged.

The existing DEBUG temporary fixture adds an explicit two-chapter preview action with an empty synthetic page. Native evidence exercises the real ExportOptionsSheet with first/second source sentinels. Xcode MCP Build919 passed. No new mirror unit test was added for this presentation-only change. Previously verified ZIP preservation tests and artifacts remain scoped to packaging, not this preview. No capability/profile/TestFlight or external sharing action is performed.
