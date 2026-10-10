# Unicode PDF mechanism comparison

Application baselinee53f444. Standalone macOS27 CoreText/CoreGraphics diagnostic, not the app backend or an iOS acceptance test. The actual native321-page output remains in qa-pdf-long-current. No application source changed.

The diagnostic draws three separately positioned runs: Vorher, fox emoji, Nachher. Both use CTLineDraw. Plain variant has no tags; tagged variant wraps paragraph and emoji span with actualText. Both generated PDFs were independently rasterized by Poppler and visually inspected: readable words/fox in the same positions, no clipping/overlap.

PDFKit and pypdf recover the fox from plain CoreText. In the actual WKWebView/UIPrintPageRenderer output both recover0of8001expectedfoxes. This supports evaluating semantic CoreText text drawing as the correction path, without proving the entire cause or iOS parity.

Tagged variant has a structure root and pypdf retains the fox, but PDFKit additionally extracts U+FFFC before span actualText. Tag presence alone does not establish correct extraction. Raw output retained. pypdf warned about wrong-pointing unused object offsets in these diagnostic CoreGraphics PDFs; this is not a strict PDF-conformance pass.

Decision: evaluate a semantic CoreText backend with per-block/inline text and logical headings/lists/tables/images mapped to pages. A blanket tag or whole-document actualText wrapper around WebKit page painting cannot prove reading order or exact copying. Keep existing backend until replacement meets current themes, images/tables/notes/links/TOC/manuscripts, pagination, cancellation and independent-reader acceptance; no silent feature reduction for one fixture.

Next proof: iOS27 Unicode/emoji fallback and extraction, rich pagination/tag semantics, exact long output, PDFKit copy/search and VoiceOver structure, no duplicated replacement characters. The app defect and untagged gap remain OPEN. This diagnostic does not close R04/R13 or deliver TestFlight.
