# Repository consolidation — 2026-10-11

The previously untracked Automerge source fork and BoundedLoader verification sources are now preserved in Git with their existing MIT licenses and lockfiles. All sixteen declared modified-source hashes match source_inputs.json. A separate manifest binds every preserved untracked source file. Existing reports describe the partial coverage and remaining packed-column limits; no new runtime or security certification is asserted.

The production module still selects upstream Automerge Swift 0.7.2 by URL, not this fork. Generated XCFrameworks/caches remain ignored. The upstream CI YAML was preserved outside the checkout because GitHub is used only as a code repository. No repository workflow was added. This preservation does not enable incoming untrusted collaboration decoding or resolve iCloud, native device or release gates.

Before consolidation, origin/main was an ancestor of c30277b with 194 commits to integrate and no divergent commits. The current product sources already passed the retained 640-headline Swift suite (four optional skips), 58 XCTest tests, and unsigned Debug/Release builds. No product-source changes were made in this consolidation.
