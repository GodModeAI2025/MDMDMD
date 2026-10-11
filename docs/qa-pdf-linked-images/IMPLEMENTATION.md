# Linked images in semantic PDF

Linked-image fragments now propagate their target through semantic traversal into the document writer. URL/named-destination annotations use the image's actual placed rectangle, after any page promotion. Targets pass the existing safeLink policy before placement. A rejected target closes the writer and prevents retrieval of partial output.

Evidence: all 66 export tests passed. A real PDFKit regression verifies twenty URL annotations over multiple pages, exact independent target set, natural oriented image frame width/height, indentation and content bounds. Another parsed Markdown regression uses a linked image targeting heading-1 and resolves its actual destination page. Unsafe javascript input is rejected and cannot produce a finished artifact.

Direct unsigned Xcode simulator compilation passed, terminal exit 0 and BUILD SUCCEEDED, work/pdf-linked-image-xcode.log. The prior MCP bridge was unavailable; no new MCP build claim.

No app backend switch: the active app PDF route remains WebKit. Tables, accessible image alt text/tagging, heading keep-with-next, inline image flow, list hanging indentation and note presentation remain open. The current tests verify annotations and text with macOS PDFKit, not physical iOS tap behavior or full visual pagination.
