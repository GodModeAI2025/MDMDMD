# Export preview identity and asynchronous blog copying

2026-10-11. Source base a2d1ffb plus this patch. verification.json binds the implementation, regression test and build/test logs.

The previous LivePreview task identity hashed image bytes and paths but omitted declared media types. Changing only image/jpeg to image/png therefore left the task identity unchanged, even though actual export validation changes from success to unsupportedAsset. The shared ExportPreviewFingerprint now includes media types, all captured document metadata/themes, framed collection counts and chapter order. Sorted asset keys keep an equivalent dictionary's insertion order from creating a different request. PDF preparation uses the captured input/profile consistently.

Two regressions verify actual HTML export success followed by rejection of identical image bytes with a mismatched media type, with distinct single-page and manuscript preview identities. They also verify stable asset order, source field boundaries, chapter order and metadata changes. This is model/render/identity evidence; no current native stale-preview reproduction is claimed.

Blog copying formerly parsed/rendered directly on MainActor. It now captures input/profile and uses ExportWorker for semantic rendering and UTF8 clipboard payload preparation. The existing busy/cancel/disappearance lifecycle owns that task; cancellation is checked before assigning UIPasteboard. A failed or canceled render cannot reach the success assignment. Successful copying retains the existing HTML/plain-text clipboard contract and image-upload warning.

The full suite passes: 618 Swift Testing headline tests with four opt-in skips, plus 58 XCTest. Existing worker cancellation/late-result and blog content tests pass alongside the new identity cases. Unsigned Debug Simulator and iOS Release compilation pass.

Limits: large fingerprint hashing still occurs synchronously when SwiftUI evaluates its task identity; this patch does not claim a complete large-document responsiveness audit. Synchronous parser/HTML/system work can only stop at its next checkpoint. Actual UIPasteboard, rapidly changing native previews, VoiceOver/keyboard behavior and physical-device timings remain unverified. Xcode/device access, current-source signing/provisioning and TestFlight delivery remain open. No capability, portal or release change occurred, and the complete R01-R15 scope remains binding.
