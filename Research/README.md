# Isolated development prototypes

These sources are retained for provenance and further development. They are excluded from the native Xcode target and root Swift package; their verification does not certify a shipping app feature.

| Original path in historical reports | Current location |
|---|---|
| Server/WorkspaceService | WorkspaceService |
| Modules/SkriptumCollaboration | SkriptumCollaboration |

The app uses iCloud/CloudKit for library sync. WorkspaceService is an earlier independent service prototype. SkriptumCollaboration contains isolated Automerge research, its original manifests/lockfiles, vendor licenses and bounded-loader verification. Existing historical evidence is retained without rewriting its source hashes. Git history preserves the original trees.

Relative paths within each prototype are unchanged. Production Sources, Tests, Config, project.yml and Package.swift continue to use their original locations. GitHub is the code repository; no Actions workflows are added.
