# Reject assistant patches on trashed pages

An assistant proposal captured against a page already in the trash could pass the revision and block-scope checks. `LibraryStore.apply` now rejects such a target with `LibraryError.trashedPage` before mutating the candidate. Revision conflicts and active-edit protections remain in force.

The disk-backed regression first failed with six assertions against the old implementation, then passed with the guard. It checks unchanged snapshot, revisions, exact library file bytes and reopened state after rejection; ordinary pages and pages restored from trash still accept scoped patches.

Full native SwiftPM verification passed: 171 Swift Testing tests and 5 XCTest tests, zero failures. Independent review: TRASHED_PATCH_REVIEW.md. This closes the specific patch admission defect; scheduling/server execution and the complete application acceptance remain open.
