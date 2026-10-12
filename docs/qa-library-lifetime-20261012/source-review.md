# Independent library presentation source review — 2026-10-12

Read-only review under app-resizability skill. Base HEAD f3b5e8c9d64a6e8670ae1a65797cbf985aa3824e. Exact reviewed SkriptumApp.swift SHA256: 2ef8965e4da2370aaa1634f2ebbcd34e7bb8b14a4ced3b2139dcdd96583902df; diff 64 insertions, 2 deletions. No source/UI/build/session actions performed.

## Source findings

- First Scene remains DocumentGroupLaunchScene; DocumentGroup and both typed WindowGroups remain unchanged. No document infrastructure or CloudKit delegate handling removed.
- Presenter resolution uses only anchor.viewIfLoaded.window.rootViewController and that local controller chain; no global application/scene/window enumeration. Window attachment and transition guards remain dynamic.
- App @State retains observable LibraryLaunchCoordinator. It strongly retains the hosting controller; UIKit also retains the presented controller. The host is created once while controller != nil, so an anchor recreation does not itself replace WritingWorkspace or its @State selection/draft/navigation state. This is source-supported retention, not runtime rotation proof.
- controller is ObservationIgnored; presented is observable and read by LibraryLaunchBackground. Close closure weakly captures coordinator. Anchor callback weakly captures controller; no obvious controller/self retain cycle. Deferred task and viewDidAppear both retry attachment; duplicate presentation is guarded by retained controller.
- UIKit external dismissal is not synchronized back to coordinator. The only reset is the explicit close completion. Native testing must establish whether any platform path dismisses/releases this modal unexpectedly; otherwise a retained offscreen host could prevent reopening. Not a proven observed failure in this review.

## Environment boundary: acceptance still open

UIHostingController(rootView: WritingWorkspace(...)) creates a separate SwiftUI root. The diff does not explicitly forward openWindow, supportsMultipleWindows, scenePhase, or the document-creation environment. Public SDK declarations and Apple documentation establish their scene/environment use, but do not establish that this manually presented hosting controller inherits the prior launch root’s values. Thus neither automatic propagation nor definite failure is proved here.

Concrete consumers requiring native checks:
- WritingWorkspace: New Library Window uses supportsMultipleWindows and openWindow; NewDocumentButton needs document infrastructure.
- ICloudSharedCatalogView: shared-window opening uses those two values; refresh uses scenePhase.
- PageWritingView: scenePhase inactivity calls finishTyping and releases edit token. Check pending typing survives background/foreground and process recovery.
- LocalScheduleForegroundRunner and ICloudOwnerForegroundRunner already read the attached local UIWindowScene via WorkspaceSceneActivityReader; their activation does not depend on inherited SwiftUI scenePhase.

Do not hardcode phase or multiwindow support. If propagation fails, capture the relevant environment from the existing scene and route/observe it dynamically, preserving root state rather than reconstructing it per phase.

Primary sources inspected: local iPhoneOS27 SwiftUI swiftinterface (UIHostingController.init(rootView:), EnvironmentValues declarations); Apple https://developer.apple.com/documentation/swiftui/environmentvalues/openwindow and https://developer.apple.com/documentation/swiftui/uihostingscenedelegate. These support scene-aware APIs, not this candidate’s native success.

## Detected queue coverage

Compared work/resizability-source-audit-20261012/TASKS.md against current source:
- PageWritingView bottom action bar: safeAreaBar remains applied.
- ICloudShareSceneRouting: already scene-migrated, application-owned BGTask/APNs preserved. Fresh configuration experiment is reverted in current source (copy original retained); queue’s final “current two-line candidate” paragraph is stale and must be updated to report deliberate failed experiment removal, not silently dropped target.
- SkriptumApp original SwiftUI Scene/adaptor responsibilities preserved; current extra presentation-lifetime fix reviewed above.
- No newly introduced global screen/orientation/idiom/guide use in exact diff. Original full-production detection remains tracked; no detected target silently dropped by this diff.

Verdict: source retention/local-window design is coherent, with environment and dismissal acceptance unresolved. Do not claim rotation, resizing, multiwindow, draft-flush, or full R10 completion from this review.
