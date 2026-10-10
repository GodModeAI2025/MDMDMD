# Semantic PDF document writer

Worker-local ownership of the PDF context, output bytes, theme and page cursor. Paragraphs use the two-pass renderer; bounded upright images share its cursor. Title, author and Scriptum creator metadata are written at context creation. Empty documents emit one valid page. Every write checks cancellation; a throwing write closes the context and permanently rejects finish, preventing publication of partial output. Successful finish is single-use. Deinitialization closes unfinished contexts.

Evidence: 61 export tests passed; Xcode MCP simulator build succeeded. Real PDFKit tests check 200 retained foxes across multiple pages, title/author metadata, one-page empty output, rejection after finish, rejection of partial output after a page-budget error, and twenty oriented images followed by recoverable text on the final page.

Limits: image test proves pagination and subsequent text, not independent raster inspection of all twenty images. This writer remains internal and unused by the active WebKit app export. Mixed Markdown block traversal, headings/TOC, tables, notes, tagged accessibility, native app export and current-source Release testing remain open.
