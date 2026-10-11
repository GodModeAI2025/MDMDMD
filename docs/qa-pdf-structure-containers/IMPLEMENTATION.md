# Logical quote/list/endnote containers

Internal tagged PDF writer now owns a balanced logical parent stack. Groups attach under the current parent and text/figure leaves attach under the innermost group. These groups do not open page content sequences and can span pages. Unbalanced finish or root-pop errors close the writer and cannot yield partial output.

Semantic traversal uses an explicit work stack with begin/end items. Quotes become BlockQuote, lists become L with LI/LBody children, and rendered endnotes become Note groups with their number and body paragraphs. Drawing text, prefixes and geometry remain the same in untagged and tagged modes.

Evidence:80export tests pass. A real PDFKit container fixture compares exact tagged/untagged text and checks Document children BlockQuote/L/Note. Independent strict pypdf verifies two LI/LBody/P chains, full parent links and zero warnings. A nested quote fixture spans multiple pages, retains200foxes and one logical200-item paragraph under Document/BlockQuote/BlockQuote/P. Unbalanced group completion is explicitly rejected.

Direct unsigned Xcode simulator compilation passed (arm64/x86_64), terminal exit0/BUILD SUCCEEDED (work/pdf-container-xcode.log); the final additional multi-page test is test-only and all export tests were then rerun.

Limitations: list prefixes still draw inside paragraph body rather than separate Lbl content; hanging indentation remains open. Notes are endnotes and inline references/link OBJR relationships remain open. Tables/repeated headers, decorative artifacts, full reading-order/resource/native/assistive-technology/PDF-UA acceptance remain open. Tagged output still defaults off; active app PDF route stays WebKit. No Release archive or TestFlight delivery claim.
