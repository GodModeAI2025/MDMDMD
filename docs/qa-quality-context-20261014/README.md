# Proofreading context — 2026-10-14

A correction dialog previously displayed only the flagged word or phrase. It now shows up to 80 whole characters on each side within the source line, marks the actual occurrence with bold text, underline and tint, and labels truncation explicitly. An additional text label identifies the marked phrase for accessible reading. The excerpt remains literal, including Markdown punctuation. All review engines prepare the excerpt through the shared `QualityFinding.make` boundary; the dialog does not reparse the manuscript.

The full-byte and revision correction admission remains unchanged. Context is not authorization to change text. The regression cases cover occurrence identification, document/CRLF boundaries, emoji/combining accents at clipping boundaries, literal Markdown, and rejection after source edits.

Evidence:

- Before implementation, the four new tests failed to compile because `QualityFinding.context` did not exist.
- After implementation, the complete writing-quality module suite passes: **46 tests**, including all four new context tests. Actual native iOS grammar coverage is not tested by this macOS package run.
- Generic iOS Debug build passes, without signing, installation or upload. XcodeGen added only the context source reference to the generated project.
- Existing concurrency warnings in unrelated focus/binding/preferences code and the App Intents metadata warning are retained in `ios-build-summary.log`; no warning arose in the changed context files.
- Xcode MCP was contacted. Its open request requires a fresh local confirmation; no MCP build success is claimed.

`verification.json` binds the checks to exact source hashes. Build 8 remains the separately delivered TestFlight/App Review snapshot. This source improvement has not been uploaded, visually verified at runtime, or used to close R14's 20-language grammar/style requirement.
