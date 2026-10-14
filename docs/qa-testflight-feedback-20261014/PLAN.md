# TestFlight feedback remediation, 14 October 2026

Four new screenshot reports concern 1.0.1 (8), iPhone 17 Pro Max / iOS 27.2. All four original attachments were downloaded and inspected. Raw portal metadata stays in the local work folder; this folder retains only report IDs, build/time, comments and screenshots. The unfiltered portal list contains 18 reports in total: four new, four from build 4, five from build 3, five from build 2. No crash feedback is displayed. Older reports are cross-checked against the existing build-3/4 remediation records, not considered fixed just because their build is older.

## Priority and acceptance

| Priority | Feedback / cause | Implementation | Acceptance |
|---|---|---|---|
| P0 | iCloud activation and sharing fail despite a signed-in account | Replace read access to filesystem ancestors with search-only traversal; retain final directory ownership, no-follow and private-file checks. Classify CloudKit and local storage errors rather than blaming login universally. Preserve durable queues. | Root-read-denied sandbox reproduction fails for old access and passes search-only access; storage/symlink/restart tests pass; activation errors and pending-share states report their actual category. |
| P1 | Comments inspector is vertically torn with huge blank areas | One top-aligned inspector layout with consistent paper background, scrollable full-height content, no 360-point content cap. | No nested fixed-height review panel or vertically centered picker; comments/revisions use available height. |
| P1 | Each block should grow to fit; no per-block scrolling | Remove composite/raw block viewport caps and internal text scrolling, preserving the page scroll and native editing/undo/caret behavior. | Every block reports full text height, including raw composite Markdown; existing editing regressions pass. |
| P2 | AI notices in iCloud settings imply missing features despite working PCC | Remove unrelated AI-access section from iCloud. Provider setup remains in KI-Zugang. | iCloud shows only library/sync/conflicts; no provider inventory in sync flow. |

## Older feedback to preserve and verify

Build 4: explicit chat edit applies to its selected scope; applied/rejected status is truthful; undo survives editor mode changes; composer and context are distinct; dispatch is the user's authorization for the displayed recipient/scope. Build 3: editor-first controls, formatting icons, visible caret, immediate keyboard, block-or-page proofreading/rewrite/summary. Build 2: toolbar overlap, finger reordering, optional own-server-free writing checks, Image Playground, keyboard activation. Refer to ../qa-testflight-feedback-20261012, ../qa-testflight-keyboard-feedback-20261011 and ../qa-writing-feedback for original evidence. Native comprehensive 20+ language grammar/style research is not shipped and is not made a release claim.

## Release sequence

1. Preserve isolated rule-engine research separately (commit 8f8f36c); it remains excluded from the app.
2. Implement the four current feedback corrections and meaningful regression tests.
3. Run relevant model/editor tests and native generic-iOS build; archive/sign a new build number. No physical-device/multiple-device gate is restored.
4. Validate distribution entitlements, production CloudKit schema, version and archive contents; retain all release proof.
5. Upload the new build once, confirm Apple processing and internal TestFlight availability.
6. Replace the currently waiting 1.0.1 (8) review submission with the verified new build, update accurate release/reviewer notes, and submit. Confirm the portal's resulting state; do not confuse submission with approval/publication.
7. Keep Git clean and pushed; no GitHub workflows. Jimdo remains separate.

## Limits

The screenshot's generic message does not identify the device's underlying error. The root-directory bug is reproducible in a macOS sandbox and exists in the iCloud code, but this is not proof of the exact iPhone error or of live multi-device sync. Improved diagnostics must preserve that distinction.

## Added user requirements

The user explicitly requires a native macOS application and a better-matching icon background. The native macOS target must compile against macOS 27 using SwiftUI/AppKit, share the document and iCloud domain models, and provide Mac text input/undo, file dialogs, windows, commands, export themes/live preview, proofreading, provider access and CloudKit sharing/comments. This is a separate platform release, not proof from an iOS build or a Catalyst target. Sign/archive/test evidence and the actual Mac App Store/TestFlight state must be recorded separately. Icon identity retains the handwritten S and ink spots, with subtle light paper and dark charcoal surfaces.
