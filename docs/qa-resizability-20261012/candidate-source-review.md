# Latest scene configuration candidate source review

Independent read-only review, 2026-10-12. Base c958966ce0988384c28969536aafbebec1176cb9. Current diff is exactly two lines in two production files; reviewer made no source/UI/session changes.

## Current candidate

- PageWritingView.swift:182: safeAreaInset(edge: .bottom) → safeAreaBar(edge: .bottom). This preserves all conditions, action controls and interior layout and completes the original safe-area task target.
- ICloudShareSceneRouting.swift:22: replace copying the existing session configuration (including its configuration name/properties) with UISceneConfiguration(name: nil, sessionRole: session.role). The existing guard returns session.configuration unchanged for non-window roles. The window role still assigns only ScriptumCloudShareSceneDelegate as delegateClass and returns that configuration. Background-task registration, conditional APNs registration, push callback, all share/invitation handlers and actual scene delegate are unchanged.

No collateral production diff found. SkriptumApp.swift has no diff; the previous foreground-presentation experiment is entirely reverted. The prior source-review.md is historical review of that failed experiment, not validation of this current candidate or proof of rotation success.

## Documentation consistency

The saved Apple UIApplicationDelegateAdaptor documentation (apple-delegate-adaptor.md:116–139) constructs a fresh UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role), sets delegateClass for the window role, and explicitly states only the delegate class is needed because SwiftUI creates/manages the delegate instance. The current window-role branch matches that configuration pattern. Its non-window guard deliberately preserves existing behavior outside scope.

This source change avoids retaining configuration properties outside Apple's demonstrated delegate-only SwiftUI integration. Source review does not establish that retained properties caused the observed rotation failure, or that fresh configuration fixes it. Those causal/behavioral claims depend on separate native before/after evidence.

## Coverage and limits

The actual UIWindowSceneDelegate and UIApplicationDelegateAdaptor remain; this is not deletion of legitimate application lifecycle registration. The sole actionable initial resizability source target is covered, and no new screen/idiom/orientation/inset arithmetic is introduced. Fresh native phone rotation, iPad resizing and share callback behavior remain runtime checks. No R10 completion claim.
