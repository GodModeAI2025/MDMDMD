# Project structure and cleanup

Updated 2026-10-11. Scope selected by the owner: tidy code and structure, retain QA evidence.

`project.yml` owns the native Xcode target configuration. Root `Package.swift` builds shared components and the curated `SkriptumWorkspaceModel` subset. Its 39 source entries are unchanged; native UI/resource exclusions are now explicit and the source list is readable. SwiftPM's unhandled-source/resource warnings are eliminated in the verified test run.

`README.md` links requirements, acceptance, release preflight, licensing and the German/English privacy-policy drafts. It distinguishes active iCloud architecture, optional AI providers and earlier standalone research/prototypes. The workspace-service prototype remains a reference, rather than being presented as a production dependency.

Local `.build` and `Server/WorkspaceService/node_modules` caches were checked for active process references, then moved reversibly outside the product checkout. Archive:

`/Users/markzimmermann/Documents/Codex/2026-10-08/mach/work/project-cleanup-cache-20261011-163111`

`RESTORE.json` in that directory records both original and archived paths. About 768.7 MB of regular-file data moved; no disk-space saving through deletion is claimed. The checkout decreased from approximately 1.1 GB to 370 MB. Source, dependencies' manifests/lockfiles, project user settings, licenses, QA captures, PDFs, images and release receipts were retained. The untracked collaboration vendor and bounded-loader verification remain at their existing paths.

Ignore rules now cover local SwiftPM/Node/Python/editor caches and local credential files. QA logs and images under `docs/` are intentionally not ignored. Existing `.gitattributes` rules preserving captured whitespace and CRLF remain unchanged.

Verification: parsed Swift package manifest confirms exactly the same ordered 39 model sources; all paths exist and none intersects the excludes. Full Swift suite: 609 headline tests, four opt-in skips and 58 XCTest with no failures. Ten Python release-verifier regressions pass. This cleanup changes no app feature or release gate and does not establish native device or TestFlight acceptance.
