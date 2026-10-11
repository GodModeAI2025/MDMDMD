# Preserve opaque original files before recovery repair

Read-only recovery now offers an Originaldateien ZIP export alongside readable-draft Markdown export. It preserves raw library/journal/media/recovery files without parsing or repairing their contents. The archive is evidence for manual recovery, not an automatically imported valid .scriptum package. The operational .library.lock is the only excluded source path, recorded in the manifest.

RecoveryEvidenceExporter runs in a cancellation-linked background task under the same cooperative library lock used by writers. It inventories every subtree with throwing directory reads, rejects symlinks/nonregular entries and unsafe names, streams original files in 1 MiB chunks with CRC/SHA-256, verifies source membership/file versions, writes a manifest, synchronizes the ZIP and independently reads back its complete output hash. A final source recheck precedes atomic same-directory hard-link publication that cannot replace a late-created destination. Failed/canceled exports remove only their own staging output. Original bytes are never modified or removed.

Retention/admission: stored ZIP32; at most 9999 source entries plus the manifest, 1024 UTF-8 bytes per relative path, 512 MiB per original file, 2 GiB total original bytes, 16 MiB central-directory budget. These are explicit bounds, not claims of accepting every library size or process RSS. Unsupported or oversized content fails the complete export; it is never silently omitted. File metadata/ACLs/timestamps are not a filesystem image; the receipt records relative names, byte counts, SHA-256, directories and capture time. Publication requires hard links in the output filesystem; the app uses its local temporary directory before the user's share action.

Only pure synchronous disk-lock/version helpers became nonisolated. LibraryStore's mutable document state remains main-actor isolated. The foreground facade owns a new temporary output directory, awaits actual worker completion/cancellation and shares only a verified successful ZIP. The recovery view exposes busy, stop and error state. No source repair or source-journal deletion is added.

## Evidence and limits

Four Core regressions cover opaque damaged bytes/checksums, existing destinations/symlink rejection with no published partial archive, directly canceled API requests/recursive destination rejection, and sparse-file admission failure. A facade regression exports a protected library without changing its bad journal or durable metadata. Full-suite/unsigned compile receipts and source hashes record integration.

INDEPENDENT_READER_RESULT.json comes from the actual current Core helper. Python zipfile checks every ZIP CRC and manifest SHA, exact original bytes/names and an empty directory; macOS unzip -t also exits zero. The fixture includes an 8 MiB binary spanning multiple read chunks, Unicode filenames and damaged binary JSON. A second live-helper test watches its owned stage marker, then creates a target while a 64 MiB fixture is being archived: destinationExists is returned, the new target remains byte-for-byte unchanged and staging is removed. Reproduce with ProcessHelper and independent-reader-proof.py. The saved receipt is scoped macOS Core/process/reader evidence, not iOS Files or native sharing.

Cooperating library writers are excluded; version/membership rechecks detect other ordinary changes. This is not hostile filesystem-race protection, NSFileCoordinator/two-device CloudKit proof or power-loss persistence. A pre-canceled request does not prove mid-stream/native stop latency. UI dismissal cleanup, actual sharing, large-volume/resource/ZIP64 matrix and complete recovery/repair UX remain open.

Fresh native QA again found the old NativePickerOwnedProxy Xcode access dialog (PID24613), MCP Permission disabled/server not running. No dialog/permission/server/bridge/session/install/device action occurred. Section/button/progress/stop/error/share/navigation remain natively unverified. Full R01-R15 and signing/current-source TestFlight remain open; no pending confirmation was treated as approval, and no provisioning/upload occurred.

Reproduction from the repository root:

```sh
swift build --package-path docs/qa-recovery-evidence/ProcessHelper --disable-sandbox --scratch-path /private/tmp/ScriptumRecoveryEvidenceProof --skip-update
SCRIPTUM_PROCESS_PROOF_BINARY=/private/tmp/ScriptumRecoveryEvidenceProof/debug/LibraryProcessProof python3 docs/qa-recovery-evidence/independent-reader-proof.py
```

Final integration: 597 Swift Testing headline with three optional external/native skips, all 58 XCTest passing; final unsigned Debug Simulator and iOS Release builds succeed. SOURCE_HASHES.json and binary receipts identify the checked sources.
