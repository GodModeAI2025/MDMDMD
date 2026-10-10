# Literal HTML preprocessing protection

Regression reproduced custom footnote extraction and contents preprocessing inside a raw pre HTML block. Export policy renders raw HTML as visible escaped text; treating its example markers as real directives changed meaning.

The shared AST line protector now includes HTMLBlock as well as CodeBlock. Marker-bearing HTML remains literal while a real footnote after the block is still rendered. The fixed regression checks escaped pre markup, unchanged literal definition/TOC syntax, absence of navigation/unreferenced footnote side effects, and the real note. Existing raw HTML warning/output policy and source storage are unchanged. Full suite480 Swift Testing headline(three optional skips),58XCTest passes. Direct new evidence is HTML output; no external reader/device or complete HTML roundtrip claim. No capability/profile/upload mutation.
