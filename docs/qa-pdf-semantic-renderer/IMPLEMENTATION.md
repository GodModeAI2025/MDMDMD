# Initial semantic Markdown PDF traversal

Connects parsed Markdown to the worker-local PDF document writer: paragraphs, headings and their named destinations, inline bold/italic/strike/code/links, code blocks, quoted/list containers, original image attachments and numbered footnotes with cross-page destinations. Container traversal uses an explicit stack and checks cancellation. Font and theme values use existing validated adapters.

Named destinations are now recorded at the first line's actual placement after page promotion, rather than at the old page position before layout.

Evidence: 63 export tests pass. The new real PDFKit test parses Markdown containing all supported blocks, includes 100 further paragraphs to force multiple pages, recovers expected visible text, verifies the URL annotation, resolves the footnote link to a page containing its actual text, and checks unchanged source image bytes. A table regression confirms explicit rejection instead of content loss.

The previous Xcode MCP socket connection was refused; no MCP success is claimed for this change. Direct unsigned Xcode simulator compilation succeeded (arm64 and x86_64; terminal exit 0 and BUILD SUCCEEDED).

Not yet production-ready: active app backend remains WebKit. Tables, thematic rules, automatic/explicit TOC and linked-image annotations are explicitly unsupported. Image alternative text tagging, heading keep-with-next, true inline image flow, list hanging indentation, continuous paragraph spacing across text/image fragments and accessible tagged structure remain required. Footnotes currently render as an endnote section. Destination naming must be aligned with the existing global heading-link resolver before production activation. No TestFlight delivery or native app export acceptance is claimed.
