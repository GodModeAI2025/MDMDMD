# Shared logical Document parent

Internal tagged PDF output now creates one Document element under StructTreeRoot, with title and input language. Text/heading/code/figure elements attach under that Document rather than directly to the structure root. Child insertion order follows actual writer traversal. The root has an availability-checked Swift owner wrapper across the package's macOS13 boundary; no unchecked CoreFoundation cast is used. Tagged output remains explicitly opt-in/default false.

Evidence:78export tests pass. Existing200line/10page paragraph structure remains one logical paragraph under Document with all Unicode preserved. Semantic H1/P/H2/Code order and per-element language tests now also verify Document role and de language. Standard figure Alt acceptance remains green. Independent strict pypdf verifies Document/Figure roles, document language, exact Unicode alternative text and both parent links (Figure→Document→StructTreeRoot), with zero warnings.

An initial conditional cast directly from Any to the CoreFoundation structure type was rejected by Swift's type-checker; replaced with an availability-scoped Swift owner wrapper before test execution succeeded.

Language is on the logical Document element, not yet catalog Lang. List/quote/table/note hierarchy, annotation object references, repeated-header/artifact policy and assistive-technology/PDF-UA/native export acceptance remain open. Active app route stays WebKit; no signed archive or TestFlight upload.

Direct unsigned Xcode simulator compilation passed (arm64/x86_64), terminal exit0/BUILD SUCCEEDED, work/pdf-document-root-xcode.log. No fresh Release compilation claim.
