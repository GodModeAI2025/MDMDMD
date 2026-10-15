# Markdown image import — 2026-10-15

## Result and scope

Implemented R04/R07's missing path from ordinary Markdown plus relative images into a durable library. Focused package verification passes **38 test definitions / 62 cases**, terminal session **23478**, exit **0**. Native SDK builds and the combined integration run belong to the parent task; this report does not claim app/device execution, live File Provider/CloudKit operation, upload or delivery.

On iOS use **Dateien → Markdown mit Bildern importieren**; on Mac use the native File menu's same command. The shared sheet asks for a folder and then specific Markdown/text documents. It shows progress and actionable errors. Files selected individually never cause neighbouring files to be opened; an image-bearing file directs the writer to the explicit folder workflow. No Space produces a clear instruction to create one.

## Data and access contract

- Strict UTF-8 import preserves the original bytes, including BOM, CRLF, decomposed Unicode and source/reference-image syntax. The CommonMark parser discovers actual images; fenced/inline code does not trigger asset reads.
- An image's original destination is immutable `MediaAttachment.sourcePath`. Physical blobs remain `media/<UUID>`. Preview, inventory, conflict resolution and export resolve that page-local binding; canonical Unicode equivalence cannot silently change its spelling.
- Coordinated file access uses the URL supplied by `NSFileCoordinator`. A file-only grant opens only that file. Folder imports open the coordinated folder, pin a descriptor and walk every child component with `O_NOFOLLOW`. No image download, external path traversal or automatic access to another directory occurs.
- Images are validated and staged before a single library commit publishes all selected documents. Destination writes also pin the library/media directories, use exclusive `linkat`, verify bytes and synchronize them. Rollback only removes files this transaction created whose identity and metadata remain unchanged. If a commit may already have published its images, positive durable-state proof is required before deleting any blob; uncertainty retains blobs.
- Library/pakage version 2 marks original-image-path metadata, while alias-free version 1 remains readable and writable. Current readers accept both. A released version-1 library/package reader rejects version 2 before it could strip `sourcePath`. Cloud wrapper and shared-checkpoint compatibility are coordinated by the parent task and verified separately.

## Export and roundtrip

The same attachment bytes feed HTML, DOCX, EPUB, blog and semantic PDF export. The source ZIP preserves Markdown byte-for-byte and writes decoded filenames, so `./images/Cafe%CC%81%20one.png` resolves to the actual image after extraction. Distinct URL spellings may share an entry only when the decoded UTF-8 filename and bytes are identical. Case/Unicode ambiguity, reserved package paths and file/directory prefix collisions fail explicitly.

The test actually generates a ZIP, extracts it with macOS `/usr/bin/unzip`, imports the extracted document into a library, and checks the source/image bytes again. It also exercises two manuscript chapter directories and reimports the app's own canonical `media/<UUID>` image references.

This exposed a pre-existing ZIP header problem: DOS creator metadata made Apple's unzip transcode UTF-8 filenames. The writer now records a Unix creator with readable regular-file `0644` attributes; both filename preservation and subsequent readability are part of the passing roundtrip.

## Retained failures and corrections

All intermediate logs remain beside the final log; they are evidence of development, not current passing results.

| Session | Exit | Finding / correction |
|---|---:|---|
| 32057 | 1 | Foundation's UTF-8 `String(data:)` removed BOM; replaced with validating byte-preserving decoding. |
| 20975 | 1 | Storage path initialization failed, and the integration fixture did not use an owned `Documents/Skriptum` location. |
| 44837 | 1 | Actual non-ASCII ZIP extraction failed; Core and alias tests passed. |
| 31824 | 1 | Captured unzip's illegal filename conversion; changing the process locale did not fix the archive. |
| 60594 | 1 | Unix ZIP creator required corresponding file permission/type attributes; zero attributes yielded unreadable files. |
| 23478 | 0 | Final import, preview, export, source ZIP and reimport checks passed. |

The storage-specific probe isolated another concrete platform detail: Foundation can shorten `/private/tmp` back to the symlink `/tmp` even after `resolvingSymlinksInPath()`. POSIX `realpath` now resolves only the library's parent, while its unchanged final component and media directory remain subject to no-follow/identity checks. The real package regressions also cover the system alias, directory replacement, external-file preservation and uncertain-publication rollback predicate.

## Bounds

Supported images follow the existing PNG/JPEG contract: maximum 32 MiB, a single image, bounded decoded dimensions. Markdown is limited to 16 MiB and the selected import to 512 MiB total. The catalog is bounded to 1,000 documents / 10,000 entries and does not follow symlinked directories. Images using `..`, absolute/network paths, query/fragment targets, ambiguous filenames or reserved source-ZIP roots are rejected. Resources referenced only by raw HTML and links to other documents remain unchanged text and are not collected; the sheet states this. There is no implicit text-only fallback after a missing or unsupported image.

## Reproduce and evidence

From the repository root, run:

```sh
swift test --scratch-path /private/tmp/ScriptumMarkdownImportTests --no-parallel \
  --filter 'MarkdownImportTests|MediaAttachmentSourcePathTests|MarkdownPackageTests|MarkdownImageImportIntegrationTests'
```

The recorded run used a dedicated task-local scratch with existing pinned dependency checkouts and `--disable-automatic-resolution`; the exact command and terminal handles are in `STATE.json`. `SOURCE_HASHES.json` binds the 25 relevant source/config/test files. `SHA256SUMS` binds the retained evidence. Large build/dependency caches remain outside Git and are disposable after the parent's combined verification; no original QA or source material was deleted.
