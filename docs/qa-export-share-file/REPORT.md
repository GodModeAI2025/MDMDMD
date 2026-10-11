# Cancellable export share-file publication

2026-10-11. Source base 7bf42c5 plus this patch. verification.json binds implementation, integration, project and test hashes.

## Problem and implementation

ExportOptionsSheet previously wrote the complete artifact with synchronous Data.write(.atomic) on MainActor. Large file publication could therefore block the interface after rendering. There was no cancellation checkpoint inside that write.

Every file-sharing format now uses ExportShareFile. Its detached ExportWorker creates an exclusive, mode-0700 temporary directory, writes a private .partial in 256 KiB chunks, checks cancellation between writes, checks the byte count, synchronizes and closes the handle, and renames to the final filename. The share sheet receives the URL only after successful completion and cancellation admission. An actor records directory ownership so a canceled late worker result also cleans up after the worker has terminated. Existing directories are rejected by atomic mkdir and are never claimed for cleanup. Successful files remain in OS-managed temporary storage for the receiving process.

The app also rechecks cancellation immediately before admitting the sharing state and removes its own returned directory if that check fails. Display names retain Unicode while path separators/control characters are sanitized; extensions accept only bounded lowercase ASCII letters/digits. The generated Xcode project includes the new source file.

## Evidence

Five new regression tests cover:

- Actual parent Task cancellation during an in-flight 2 MiB disk write, returning CancellationError and no surviving owned directory.
- Exact byte readback of a sliced 800 KB binary Data value, Unicode filename sanitization and absence of a staging file after success.
- Injected cancellation before chunks, during chunks and after the final rename, with complete cleanup and no admitted URL.
- Mid-write out-of-space error, an untouched preexisting directory/sentinel, then a successful independent empty-file retry.
- Unsafe extension rejection before creating any files.

The final full suite passes: 616 Swift Testing headline tests, four opt-in skips, 58 XCTest. Explicit --no-parallel avoids the separately documented PDFKit/AppKit test initialization stall. Unsigned Debug Simulator and iOS Release builds pass; the new writer and real ExportOptionsSheet integration compile in the native target. Test log and hash-bound build receipts are retained.

This proves scoped worker/filesystem behavior and native compilation. It does not prove physical-device interaction, the system share recipient completing a read, hard wall-clock cancellation latency inside an OS filesystem call, hostile filesystem races, power-loss durability or current-source TestFlight delivery. Native UI validation still requires the Xcode/device connection. No portal, provisioning, capability or release change occurred; all R01-R15 acceptance requirements remain binding.
