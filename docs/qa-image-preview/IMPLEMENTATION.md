# Bounded asynchronous image-block preview

Image blocks already existed. Their inactive row previously read/validated full attachment data during SwiftUI body evaluation and constructed UIImage/NSImage directly. Validation requested a full-resolution CGImage as well, so large-photo work could repeat while a manuscript changed.

The row now gets an immutable MediaPreviewSource containing the actual library root and attachment descriptors. The request is keyed by root, exact attachment metadata and an image-arrival generation; ordinary text edits do not change that key. A @concurrent request performs the existing scoped path/size/hash checks and encoded format/frame/dimension validation off the main actor. It never fetches a URL or accepts a path absent from the page's attachment catalog. The original full validation/read path used by import and export is retained.

A dedicated actor serializes ImageIO thumbnail decoding, uses orientation transforms and caps the resulting longest edge at 2048 pixels. Its LRU retained cache is bounded to 32 MiB using actual bytesPerRow × height. A SHA-256 content key reuses decoded thumbnails across identical payloads. This is a cache/output bound, not a claim that ImageIO internals, SwiftUI retained views or all process peak memory fit within 32 MiB. The original permitted image size remains at most 40 million pixels/32 MiB encoded.

The view stores only the thumbnail, publishes after cancellation checks, and hides an old thumbnail when its loaded request no longer matches the visible request. It displays a transient progress indicator and a stable unavailable state for missing/invalid data. Caption and accessibility image label are retained. Cloud-image acceptance publishes a directly observable per-library image generation, allowing a missing asset to retry without relying on a silently replaced optional session reference. Actual CloudKit arrival remains unverified.

No original file, Markdown source, block ID, attachment metadata, exported byte payload or provider selection is changed by preview loading. The cached preview is not written back as the export image. Composite raw-source blocks containing embedded image syntax remain a separate rich-media editor requirement; this change does not claim full R02/R07 completion.

## Evidence and limits

The full suite reports 459 Swift Testing tests (three optional tests skipped) and 58 XCTest tests without failures. Real ImageIO tests cover 3200×1800 → 2048×1152, EXIF-style orientation transformation, identical-payload cache identity, invalid data rejection, cache eviction/byte bound and scoped real-file requests. Missing/returned/corrupted attachment cases preserve the page JSON bytes. These checks do not measure scroll latency, thread samples or all memory peaks.

Xcode MCP Build880 passed. The DEBUG --scriptum-image-preview-ui-qa host creates a synthetic blue/gold 3200×1800 PNG and a real three-block temporary page. Native report/screens separately record visible preview/caption, typing, normal close/reopen, stable block IDs and original attachment bytes. No Photos access, account, CloudKit grant, network inference or existing manuscript is used. DEBUG host code is excluded from Release. Real image-rich book/VoiceOver/Dynamic Type/physical-device/performance acceptance remains open, alongside the existing provisioning/TestFlight gates.
