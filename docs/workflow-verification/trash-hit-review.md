# Independent row hit-area fix review

**PASS.** The Button label now expands to the row width before applying a rectangular contentShape, so transparent trailing space participates in the same button hit region as visible title/icon. The modifiers are inside the label, the appropriate level for a plain Button hit target. Navigation action, persistence guard, trash policy, context menu and accessibility Button semantics remain unchanged. No duplicate gesture or hidden overlay introduced. Temporary prints are absent from SkriptumApp.swift.

Root's native evidence distinguishes the prior failure: center blank-space tap triggered no navigation event, while title tap completed prepare/resolve/detail. The diff directly addresses that hit-testing cause. Confirm the formerly failing row-center tap on the rebuilt app; no new static blocker found. Read-only review, no sources/device actions changed.
