# Image Playground image-block integration — 2026-10-11

ImageBlockPicker now offers Image Playground when supportsImagePlayground reports support. The system sheet receives an empty concept array and no source image; Scriptum does not seed it with document context. The explicit allowed styles are illustration, sketch and animation, with no externalProvider style. The image's input description is entered by the user inside Apple's interface. Unsupported devices retain Photos/Files import and show a current-unavailability label.

A completion snapshots the temporary URL using the existing bounded32MiB reader and validates PNG/JPEG content/dimensions. It retains owned Data rather than a borrowed URL beyond the sheet session. The separate insert action allows editing alt text and routes through the existing performMutation/addImageBlock revision-bound transaction and source undo; cancellation/discard alone does not add a block. A failed save leaves the draft available for retry. Generation requests are not started by Scriptum automatically.

The bounded read and image validation in this callback are synchronous on MainActor. No responsiveness, actual generated format or temporary-file timing proof is claimed; non-PNG/JPEG data fails validation. Existing source/media tests exercise five XCTest cases plus one Swift Testing test with three actual image/table/history cases. They do not execute Image Playground.

Native tools remain unavailable in this Codex session. After the user reported activation, a fresh read-only status query outside the sandbox confirms host permission enabled, server running and the Scriptum folder/workspace permitted. The earlier sandbox disabled/stopped result was not authoritative host evidence; it is retained separately with that limitation. No permission/server change is needed. The session connector must reload its native tools. Real supported/unsupported devices, actual generation, cancel, temporary result, alternate text, reopen, undo, exports and availability need native verification. Current-source TestFlight and full R01–R15 acceptance remain open. Store claims were not expanded and no portal/provisioning action occurred. Privacy DE/EN drafts now describe this optional route.

Apple references checked against the installed iOS27 SDK declarations:
- https://developer.apple.com/videos/play/wwdc2026/375/ (system UI, temporary URL lifetime, styles and external-provider opt-in)
- https://developer.apple.com/documentation/swiftui/environmentvalues/supportsimageplayground
- https://developer.apple.com/documentation/imageplayground

Final unsigned Debug simulator and Release iOS builds succeeded. The selected existing media/undo tests passed. Exact source and log SHA256 values are in verification.json.
