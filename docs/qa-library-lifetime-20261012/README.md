# Library presentation lifetime — 12 October 2026

The regular library was previously presented by a SwiftUI full-screen cover attached to the document browser's decorative background. Phone and iPad verification reproduced loss of the editor during rotation; failed hypotheses remain in [earlier evidence](../qa-resizability-20261012/README.md).

The candidate keeps a library hosting controller in the existing launch coordinator and presents it from the anchor view's own window root. It does not enumerate global scenes or windows. The decorative view may be rebuilt without owning the editor's dismissal. Explicit observation of the launch request keeps the button functional. Closing dismisses only this library controller. DocumentGroupLaunchScene remains first; DocumentGroup, document undo/autosave code, share routing and the separate library-window host are unchanged.

[Actual iPad receipt](summary.json): ordinary launch without QA flags, focused existing native text field retained across portrait → landscape → portrait, library closed/reopened, and a second library window opened with the same library scope. Complete canonical library bytes and production source hashes remain unchanged. The software keyboard was not visible, so this does not certify its iPad layout.

The new library window's “Neue Markdown-Datei” menu action dismissed the menu without opening creation UI. This check does not establish whether the behavior predates this change or whether the original library controller behaves identically. Native document creation remains open. [Source review](source-review.md) records environment-dependent lifecycle checks that still require runtime evidence.

Final unsigned iPhoneOS Release compilation passes. [Phone receipt](phone/summary.json): ordinary launch retains the correct editor through landscape and portrait return, then Home → own-app activation. The exact 43-byte Unicode witness, page/block IDs, complete six-page library and all 186 current source files remain unchanged. The portrait software keyboard and writing actions are readable.

Phone rotation dismisses the software keyboard and loses input focus; returning to portrait does not restore either. Landscape body content is partly clipped above the formatting bar; scroll inaccessibility was not established. These remain unresolved defects. A static-content background round trip does not prove pending-keystroke flush or every scenePhase-dependent behavior.

Full window resizing, VoiceOver, Dynamic Type, hardware-keyboard navigation, drag-and-drop, iCloud participants and TestFlight delivery remain separate requirements.
