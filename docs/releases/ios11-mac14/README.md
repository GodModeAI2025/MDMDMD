# Scriptum 1.0.1: iOS 11 / native Mac 14

15 October 2026. New candidate after the owner's Mac-design feedback. This record initially covers preparation; upload, Apple processing, internal testing and App Review must be confirmed separately before being claimed.

## Changes

- Native Mac: compact standard title bar, named view and AI menus, consistent sidebar symbols, stateful inspector, continuous subtle paper and smaller flexible assistant dialogs. Actual light/dark, minimum-size, focus, mode and source-preservation checks are [retained](../../qa-mac-design-20261015/REPORT.md).
- Lektorat/rewriting/summary dialogs no longer dispatch an AI request merely when opened. The visible Starten button initiates the request after showing the context and selected provider. The final empty-dialog/local-provider interaction is verified. Direct chat-edit application and manual correction admission remain as implemented.
- iCloud account-access and authentication failures use distinct explanations. The bounded failure code is shown by the error and preserved when opening sharing. Fresh retry/code-retention and exact local-byte preservation are tested. **The affected iPhone's actual account condition remains unresolved**; this is not presented as a confirmed device-sync fix.
- UIKit deferred focus callback is explicitly MainActor/Sendable. Existing focus behavior and source-preservation guards stay intact.

## Verification

The complete root package run succeeds: 750 Swift Testing cases reported, four optional cases skipped, 746 actually executed; 58 XCTest cases passed. **804 tests actually executed**, no failures. All 13 distribution-verifier regressions pass. The app code also has final native Mac and iOS-arm64 Xcode MCP build receipts and a strict iOS Release compilation in the linked design checkpoint. Source and release-signature evidence for these numbered archives will be added after the actual operations.

The [real once-only Mac scheduled PCC completion](../../qa-pcc-task-completion-20261015/REPORT.md) is separately recorded; it does not establish iOS background execution or all R09 requirements. Experimental native multilingual grammar-engine research remains excluded. The full R01–R15 scope is not declared complete by this delivery.

At preparation time the existing iOS10 and Mac13 submissions still show Warten auf Prüfung. Their earlier receipts remain under `../ios10-mac13/`. No Apple terms are accepted in this step, no workflow or synchronization server is added, and Jimdo remains separate. No mandatory additional physical-device gate is introduced.
