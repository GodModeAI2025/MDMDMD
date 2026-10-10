# Semantic PDF paragraph renderer

Connects two-pass paragraph layout to a shared page cursor and caller-owned PDF context. Reserves each widow/orphan fragment before drawing, advances pages explicitly, draws strike decorations and creates link annotations. The cursor exposes its remaining page budget so paragraph planning cannot exceed the document limit. Empty paragraphs do not add spacing or pages.

Validation: all 59 export tests passed. A real PDFKit regression covers a 200-line Arabic/combining-character/emoji paragraph starting after existing page content, exact fox count, all numbered lines, consecutive page transitions, live URL annotations and annotation bounds inside content margins. Xcode MCP simulator build succeeded.

The initial test compile used incorrect Inline.link argument labels; corrected to the existing enum signature before execution.

This remains an internal foundation. Active app PDF export is still WebKit. Full semantic block integration, native app export acceptance, tagged accessibility and current-source Release validation remain open.
