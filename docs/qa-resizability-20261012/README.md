# Resizability investigation — 12 October 2026

R10 remains open. The baseline is commit `c958966`. On a regular native phone launch, the portrait editor and writing actions remain readable above the keyboard, but rotating the focused editor returns to the ordinary empty file-browser root. A stable recapture shows the same running process. The original page and production source hashes remain unchanged. See [baseline receipt](baseline-phone.json).

Moving presentation from the decorative background to the foreground button failed launch verification and was entirely reverted. Its [patch](rejected-anchor.patch) and [receipt](rejected-anchor-phone.json) are historical failed evidence, not the current implementation.

The tested candidate replaced the writing bar safe-area API and constructed a fresh window scene configuration following Apple's delegate integration pattern. [Independent source review](candidate-source-review.md) found no collateral source changes; unsigned iPhoneOS Release compilation passed. The constructor change was a hypothesis, not an established fix.

The candidate phone session disappeared before its first capture; [receipt](candidate-phone-session-loss.json). A fresh iPad follow-up confirmed ordinary launch, library access and native focused text input, then reproduced the loss of the editor on rotation to landscape. The same app process remained running. [Final native receipt](recovery-summary.json) records preserved IDs, the actual persisted input and completed session cleanup. Software-keyboard layout was not witnessed on this pass.

The scene-configuration hypothesis was reverted after this failure. Only the writing toolbar's safe-area-bar API modernization remains in production. It does not fix the rotation failure. The original first document scene and the production library presentation architecture remain unchanged pending a verified replacement.

Full window resizing, multiple-window editing, keyboard navigation, Dynamic Type, VoiceOver and actual share invitation behavior retain their separate acceptance requirements. No TestFlight delivery follows from this investigation.
