# Core material/templates wave — frozen

Files: Sources/SkriptumCore/Models.swift, Sources/SkriptumCore/LibraryStore.swift, NEW Tests/SkriptumCoreTests/PagePurposeTemplateTests.swift. No existing tests, PageLinks, App, manifests or project files changed. No commit.

APIs:
- `PagePurpose: String, Codable, Sendable` cases `writing`, `material`, `template`.
- `Page.purpose: PagePurpose?`, `Page.effectivePurpose: PagePurpose` (legacy nil means writing). Existing optional synthesized decoding remains schema 1; complete Page copies/revisions/recovery naturally carry purpose.
- `LibraryStore.setPurpose(pageID: UUID, purpose: PagePurpose, baseRevision: UUID) throws`: existing edit transaction protects active editing, stale revision, no-op semantics, historical baseline, atomic rollback. Trashed page rejected with `LibraryError.invalidTemplate`.
- `manuscriptPages(spaceID: UUID) -> [Page]`: stable snapshot order, writing only, excludes material/template/trash.
- `aggregateWordCount(spaceID: UUID, countWords: (String) -> Int) -> Int`: uses caller's prose-aware counter. Core does not pretend that raw Markdown whitespace tokens are prose counts.
- `instantiateTemplate(pageID: UUID, baseRevision: UUID, spaceID: UUID, parentID: UUID? = nil) throws -> Page`: source must live template, no active source edit, exact revision. New block/page/revision IDs; source byte sequences, media descriptors, rules/prompts/goal/tags preserved. Result purpose writing. Reuses createRecoveredPage single atomic commit + verified immutable attachment read; hierarchy/space errors and failed disk/media cannot publish a partial page/history or change source. No duplicated staging logic.

Validation:
1. `work/workflow-red.log`: scoped new test build failed on missing purpose/template APIs before implementation (initial sandbox cache error retried escalated before real RED).
2. `work/workflow-green.log`: exact native filtered command exits 0; 4 Swift Testing tests all pass. Assertions cover legacy nil decode + cold reopen, manuscript/material/template count exclusion, full metadata/exact Unicode-CRLF bytes and independent identity, unchanged source/history, non-template/stale/missing destination/invalid parent/active-edit rejection, failed atomic disk commit, valid media copy, corrupted media rollback, cross-space and trashed-parent rejection, trashed source rejection.

Root must integrate App facade/page choice/word count/export selection purpose filtering; no claim those UI flows are done by this Core patch.
