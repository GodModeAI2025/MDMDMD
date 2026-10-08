# R03/R05 — isolate imported library sessions and private assistant data

## Observed boundary problem
An imported package is an independent library but retains page UUIDs. The assistant currently keys private history only by page UUID, and all conflict recovery media use the primary library directory. Thus an independent import can reuse an unrelated library's chat or conflict-media namespace. Switching the mutable global store can also keep the same page view state when UUIDs are identical.

## Required result
Each library owns its durable recovery storage and private assistant namespace. A package activation creates a new WritingLibrary facade; existing document windows retain their original facade/store. The workspace uses a library-plus-page view identity so same-UUID imports replace the current editor without redirecting pending callbacks into another store. A new default library is used for newly opened windows and cold launch, without silently replacing existing windows.

## Compatibility and failure contracts
Keep the primary library's existing chat/recovery paths so current histories remain readable. Imported paths are scoped by their owned Documents-relative directory, stable across container relocation. Reject directories outside that root; an invalid history scope fails closed and cannot fall back to another library's history. Chat save must respect a failed/read-only initialization. Recoveries load from the owning store on construction.

## Tasks
1. Core helper and tests for primary compatibility, imported namespace separation, container relocation, URL/path boundary rejection and stable filenames. No UI/provider dependency.
2. App facade constructor/import activation and per-window ownership; assistant startup error/safe save; stable namespace injection.
3. Unit regressions for same-page-ID histories in different scopes and read-only save; real iOS build, independent review, delegated native package-switch/old-window/cold-launch verification.

The uploaded internal build remains 1139ce8. This is a following source wave, not a modification of the uploaded artifact. Native collaboration integration and server scheduling remain open.
