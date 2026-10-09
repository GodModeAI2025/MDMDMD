# R03: active block bindings must read accepted current content

The previous active row constructed its text Binding getter from an immutable rendered BlockProjection. A native edit publishes to the parent's accepted blocks, but that old getter can still return the previous render's text before the next body evaluation. Native synchronization then assigns the old text and clamps the caret backwards.

The real AppKit coordinator regression reproduced both text and caret rollback under that supplied ordering. It first failed two assertions, then passed after the getter was changed to read the current canonical source. The same row instance is retained throughout the probe. Unicode/CRLF bytes, block UUID and no-op UTF16 selection are preserved; an explicit external restoration to the original canonical source is still applied.

Production rows now supply a closure reading the parent's current accepted block by stable UUID. BlockEditorBinding projects that live source on every get, and the setter retains the existing domain-gated edit callback. Style operations use the current source provider. Native update methods delegate their existing synchronization statements to the coordinator, enabling the actual regression boundary. No text-update suppression, independent draft buffer or generation heuristic was added.

This closes the demonstrated stale-getter contract defect. It does not establish that this ordering caused the first QA11 input discrepancy; that original event still lacks a proving timeline. UIKit runtime reproduction, actual fast typing, legitimate external restoration and IME checks follow the fresh SDK/test/review freeze. No full R03/app acceptance claim is made from the AppKit regression alone.
