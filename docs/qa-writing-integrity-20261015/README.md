# Professional writing integrity — 15 October 2026

Three reproduced defects are corrected in this source checkpoint. Apple tools remain the exclusive grammar route.

## Apple grammar at manuscript boundaries

The old integrated NativeWritingReviewer misses Apple's real German `geht` → `gehen` finding in “Wir geht nach Hause.” when the sentence starts at UTF-16 offset 16,380. The short reference and other offsets succeed. Both native paths now use the existing bounded context planner; ownership follows each specific finding's absolute start, including details in sentences spanning a boundary. Spelling uses the same ownership rule. Request bounds, whole-word/Unicode constraints, Markdown protection, stale-source refusal and cancellation remain intact.

`grammar/baseline-corrected-fixture.log` records the authoritative failure. The earlier baseline retains an initial wrong dictionary assumption and is not the spelling baseline. The final entire quality run passes 83 tests in 7 suites, with both actual Apple tests enabled via `SCRIPTUM_APPLE_GRAMMAR_WITNESS=1`. All three cut positions produce exactly one target finding; application preserves outside UTF-8/CRLF/combining characters and stale revisions are rejected. A deterministic callback test covers both Apple grammar and correction results and issue-level ownership. The native witness uses synthetic text on this Mac. This is not an iOS runtime, whole-language or 20-language coverage claim.

## Consistent export heading sizes

Before correction, DOCX Heading1 at 8/13.5/36 pt body is 18.5/18.5/36 pt instead of 16/27/72 pt. PDF's existing scale is shared across DOCX, PDF, explicit HTML CSS and EPUB, rounded to Word's half-point precision. Titles use Heading1 size. Body settings and page geometry are unchanged. Actual DOCX XML, HTML/EPUB CSS and rendered PDF font sizes are compared at all three sizes for all six headings and the title. All 134 export tests pass. The preserved 13.5 pt sample PDF was rendered with Poppler and visually inspected: all levels and body text are readable, unclipped and ordered on A4. Word-specific page breaking is not inferred from semantic preview.

## AI read-only image context

The old flat regex leaks reference-image destinations and remnants of nested-parenthesis paths to captured provider requests; it also alters literal code and normalizes no-image whitespace. Four baseline definitions fail with 27 issues. The already installed Swift Markdown parser now removes actual image nodes and their obsolete definitions, and preserves visible labels of links sharing image destinations. Literal code and ordinary links remain. No-image inputs remain exact. Revision and hybrid editing targets bypass the projection and retain original Unicode/CRLF/image bytes; additional read-only references are filtered in all modes.

All six focused definitions (seven image syntaxes and both editing modes) and all 37 AI tests pass. Provider capture uses an in-process test provider; no credentials or external provider call is involved. When image redaction is needed, the read-only copy is formatted and unused reference definitions are omitted. Prompts, rules, history and literal examples are not general-purpose redaction targets. Stored documents and responses are not rewritten by this display/context helper.

## Integration and review

Both official Xcode MCP SDK builds pass: iOS in 7.488 seconds, native Mac in 4.544 seconds, with empty error arrays. Current workspace readback and full logs are retained under xcode/. Original scheme/destination restored and the owned MCP bridge stopped. Independent connected-code review found no blocking issue in grammar ownership or AI target/reference admission. SOURCE_HASHES.json binds the tested code.

No app, physical-device or simulator UI was launched. Real collaboration between two iCloud accounts and the remaining R01–R15 requirements retain their own evidence boundaries. This checkpoint prepares iOS31/Mac32; final availability is recorded separately in the release report. Existing Store submissions iOS11/Mac14 are retained.
