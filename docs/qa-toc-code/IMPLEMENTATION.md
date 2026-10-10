# Preserve contents markers in container code

The raw-line TOC isolator missed a fence opened on a list-marker line. It inserted paragraph boundaries around an indented (toc) code example, changing the code block and its surrounding document structure. BEFORE_FAILURE.txt preserves the failing exact-code HTML regression and rendered wrong structure.

TOC isolation now uses the same pinned CommonMark AST CodeBlock line spans as custom footnote extraction. Closed, unfinished and container/indented code lines remain untouched by marker preprocessing. A genuine standalone prose marker is still isolated into a paragraph and rendered as a contents list. CRLF lines now recognize the marker through newline-aware trimming. Original caller source remains unchanged.

Fast paths skip the additional protection parse entirely when the source contains no (toc), or no [^ for footnote extraction. This avoids adding redundant parsing to ordinary source with neither syntax. Matching source still needs parser passes before custom preprocessing; no latency/memory guarantee is claimed.

Three new tests reproduce closed list-fence corruption, preserve an unfinished list fence without creating navigation, and verify a CRLF prose marker separates before/after paragraphs and creates navigation with unchanged source bytes. The full suite479 Swift Testing headline(three optional skips),58XCTest passes, including prior independent DOCX/EPUB structural tests. New direct regressions inspect HTML, not external Word/EPUB reader behavior. Xcode MCPBuild1041 passes. No source file in the user's library, account, capability, profile or TestFlight artifact was changed by verification.
