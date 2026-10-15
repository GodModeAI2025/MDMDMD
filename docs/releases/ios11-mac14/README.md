# Scriptum 1.0.1: iOS 11 / native Mac 14

15 October 2026. New candidate after the owner's Mac-design feedback. Both uploads were accepted by Apple at 08:27 CEST. Processing and export compliance are complete; both builds are **Im Test** in **Mark – Intern**. iOS11 is submitted and **Warten auf Prüfung** (08:38 CEST, `4625ac11-3d3e-455a-9db9-395d8766bc2d`). Mac14 is submitted and **Warten auf Prüfung** (08:49 CEST, `64c9f5f0-8444-491d-96b6-0e88590a1e10`). Both retain automatic release after approval. No approval or publication of these new builds is claimed. See STATE.json for the last verified stage.

## Changes

- Native Mac: compact standard title bar, named view and AI menus, consistent sidebar symbols, stateful inspector, continuous subtle paper and smaller flexible assistant dialogs. Actual light/dark, minimum-size, focus, mode and source-preservation checks are [retained](../../qa-mac-design-20261015/REPORT.md).
- Lektorat/rewriting/summary dialogs no longer dispatch an AI request merely when opened. The visible Starten button initiates the request after showing the context and selected provider. The final empty-dialog/local-provider interaction is verified. Direct chat-edit application and manual correction admission remain as implemented.
- iCloud account-access and authentication failures use distinct explanations. The bounded failure code is shown by the error and preserved when opening sharing. Fresh retry/code-retention and exact local-byte preservation are tested. **The affected iPhone's actual account condition remains unresolved**; this is not presented as a confirmed device-sync fix.
- UIKit deferred focus callback is explicitly MainActor/Sendable. Existing focus behavior and source-preservation guards stay intact.

## Store delivery

The two actual native Mac14 light/dark images are submitted at 2560×1600 as unchanged raw JPEGs. Initial PNG version associations stalled in Apple validation and were replaced; those files and the bounded failure snapshot remain preserved. See STORE_MEDIA.json. Both old iOS10/Mac13 submissions were withdrawn for the replacements after new-build processing/compliance completed. Final TestFlight and submission screenshots and text are retained here.

## Verification

The complete root package run succeeds: 750 Swift Testing cases reported, four optional cases skipped, 746 actually executed; 58 XCTest cases passed. **804 tests actually executed**, no failures. All 13 distribution-verifier regressions pass. The app code also has final native Mac and iOS-arm64 Xcode MCP build receipts and a strict iOS Release compilation in the linked design checkpoint. Both Release archives succeed from clean source `4b9b222`; the exported iOS app (11) passes all 25 distribution checks, the native Mac app (14) all 28. The Mac installer certificate chain validates against Apple. Source, package hashes and upload receipts are retained here.

The [real once-only Mac scheduled PCC completion](../../qa-pcc-task-completion-20261015/REPORT.md) is separately recorded; it does not establish iOS background execution or all R09 requirements. Experimental native multilingual grammar-engine research remains excluded. The full R01–R15 scope is not declared complete by this delivery.

At preparation time the existing iOS10 and Mac13 submissions still showed Warten auf Prüfung. Both were subsequently withdrawn only after their replacement builds completed processing and compliance. iOS10 had advanced to In Prüfung before its withdrawal. Their earlier receipts remain under `../ios10-mac13/`. No Apple terms are accepted in this step, no workflow or synchronization server is added, and Jimdo remains separate. No mandatory additional physical-device gate is introduced.
