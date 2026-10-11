# Shared document paper layout — 2026-10-11

User reference: [original screenshot](../qa-shared-header/user-reference.png). The screenshot shows a large white navigation header, a truncated iCloud-unavailable title and a white bottom home-indicator strip. The shared-writing header/label correction in ad05dce already has dated portrait native evidence; its report explicitly retains the bottom-strip issue.

The separate ICloudSharedCatalogView still used the old large navigation title and default unavailable label. It now uses the same inline title, visible adaptive PaperBase navigation background, and explicit multiline unavailable label as the shared writer. Its flexible content frame and decorative outer paper background fill the offered presentation, including loading states with only a small ProgressView.

In ICloudSharedWritingView, only sidebar and detail consumer paper backgrounds extend through the bottom container safe area. Controls remain within system safe areas and keyboard avoidance remains active. The comments sheet, editor, transport, permissions and provisioning were not changed. Existing localized wording remains literal Text.

Independent source review under app-resizability checked both exact source hashes and the two-file coverage. Prerequisites pass in project and merged Release plist: LaunchScreen, all four iPad orientations, no UIRequiresFullScreen, multiple scenes enabled. No orientation override/runtime resize proof was obtained.

Native device-interaction delegate rechecked Xcode read-only after source freeze: old NativePickerOwnedProxy access dialog PID24613 still visible, MCP Permission disabled and server not running. It performed no dialog/server/session/install action. Current-source runtime appearance is unverified. Still required: catalog notConfigured/loading/empty/error states, bottom-strip disappearance, keyboard, landscape, iPad resizing, Dynamic Type and VoiceOver.

The change is reversible appearance code. No implementation-mirroring unit tests were added. The previous full-suite result (604 Swift Testing headline with three optional skips; 58 XCTest) remains evidence for the preceding PDF change, not for native layout rendering. Build receipts here describe only unsigned compilation. No signed archive, upload or current-source TestFlight installation was performed.
