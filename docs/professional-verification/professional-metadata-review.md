# Independent metadata/PDF/LAN description review

Verdict: **PASS for the inspected changes**. Fresh SDK/test results remain root gates; the supplied native PDF measurements support the geometry correction.

## Executable metadata review

Compiled current QualityCore against existing pinned official Markdown/cmark objects and ran eleven independent probes. All rejected with protectedSyntax: footnote reference identifier; quote/list definition identifiers; quote/list/nested definition destinations; continuation-line destination; multiline title body; scriptum URI, mailto URI and DOI URI. Fixture/executable are work/review-probe; compilation and execution exited 0. These independently close the six reported unsafe cases and exercise URI/continuation additions.

Lexical masks now cover metadata omitted by the CommonMark content AST, including export footnote identifiers and container-stripped reference definitions/continuations. Continuation tracking respects escaped title delimiters, resets ordinary next-line prose when a title does not begin, and preserves original UTF-16 locations. This is conservatively protective for ambiguous syntax. The AST comparison also includes public Link destination/title and Image source/title, so parsed metadata changes cannot pass merely because node kinds/nesting match. Existing exact source-byte and range guards remain in place. Eighteen metadata cases and five ordinary prose byte controls exist in the new test; no source edits made during review.

## PDF correction

The renderer uses public WKWebView/UIPrintPageRenderer behavior, not private preferences. A named 1.25 minimum shrink factor normalizes selected point dimensions before WebKit layout; UIKit remains the single owner of margins. Wrappable prose/code and fixed-layout tables reduce extra fit shrinking. Root reports actual native Letter 14-point font and A4 approximately 16.0028-point font for a 16-point selection, minimum text X=72 points and embedded image proofs. Those measurements support this adjustment on the target runtime. This factor derives from WebKit implementation behavior rather than a documented immutable UIKit contract, so retaining measured PDF acceptance checks for future SDK changes is prudent; no current blocking defect identified.

## Local-network description

NSLocalNetworkUsageDescription is present in authoritative project.yml and generated Config/Info.plist with a concrete purpose limited to the person's chosen local language-checking server. It grants no blanket transport bypass: HTTPS endpoint validation remains separate. No Bonjour discovery entitlement or unrelated network permission was introduced.
