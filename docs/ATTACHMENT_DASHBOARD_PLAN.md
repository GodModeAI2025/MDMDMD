# R15: attachment overview

The existing professional-writing requirement includes an attachment dashboard. This wave adds a source-backed inventory and native page/library overview; the app and release scope remains R01–R15.

Activation: Seitenaktionen → Anhänge und Verwendung first durably closes/saves the active editor, then opens the current page's inventory. Switch to the complete owned library, inspect filenames, MIME types, byte counts, active/trash/history usage and checked storage status. A detail view reports missing per-page metadata and retains historical references as historical records; current live pages can be opened through the existing guarded navigation path.

Core owns the immutable inventory, strict media/UUID destination parsing, actual storage audit and permanent tests. UI owns only the dashboard sheet. Root owns the page action/project integration. Separate files, frozen sources before builds and native sessions, independent review after integration.

Storage checks use the existing MediaValidation bounds/type/hash/symlink contract on the owning store's captured directory. Run off the main actor, sequentially discard validated data between attachments, and support cancellation. Unknown/conflicting metadata is not read. Read errors distinguish confirmed missing files from invalid or unsafe files. Reference counts come from actual Markdown Image/Link nodes; code and raw HTML are excluded. Pages, trash and historical revisions are separate contexts. No file cleanup is implied by a count of zero active references.

An inventory is tied to one library and snapshot. Reject completed results from another library/store or changed snapshot; show stale state and a refresh action rather than verified counts for newer content. The initial source-only inventory must say not checked, never verified. Rendering uses stable entry UUIDs, lazy rows, source-controlled text and explicit status labels.

Evidence: source tests for references, missing metadata, conflicts, ownership and strict destinations; actual disk tests for valid/missing/corrupt/symlink media and cancellation; fresh SDK build and independent review; Xcode MCP native reachability, filters, details and truthful storage states. Physical devices, very large inventories, wider accessibility and unrelated remaining requirements retain their own acceptance gates.
