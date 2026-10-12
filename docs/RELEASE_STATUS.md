# Scriptum release status

Updated 2026-10-12. This page distinguishes the development candidate from the delivered TestFlight build. The complete [R01–R15 requirements](REQUIREMENTS.md) remain binding.

## Completed in the current candidate

- Production code is separated from unshipped prototypes in `Research/`; 455 relocated tracked files retain their exact source bytes. QA evidence and licenses remain versioned. GitHub is the code repository, with no workflows.
- The ordinary editor now applies native keystrokes against the displayed syntax frame. The 43-byte Unicode witness survives editing, durable checkpoint and reopening exactly; rejected drafts are preserved separately. [Evidence](qa-input-frame-20261011/REPORT.md).
- Full local verification for the editor change: 655 Swift Testing headlines (four optional skips) and 58 XCTest, plus unsigned Release compilation. Ten signed-archive-verifier regression tests pass.
- The initial white HTML preview capture was taken before load completion; the stable preview renders correctly. The candidate adds loading/error feedback for page and HTML export previews. Official Xcode MCP verifies the loading indicator followed by actual content on first opening and after closing/reopening the regular page preview; the HTML export caller compiles in Release. [Evidence](qa-preview-loading-20261011/README.md).

## Additional export fix awaiting integration

A separate `fix/epub-author-metadata` branch omits invalid empty EPUB creator metadata. All 124 export-test headlines (one optional skip), unsigned Release compilation and six current-renderer EPUBCheck validations pass. Three 24-chapter profiles preserve paragraph/Unicode/table/footnote/TOC counts independently. [Evidence](qa-epub-conformance-20261012/README.md). Actual Apple Books import requires a concrete confirmation after automatic approval rejected its potential library/synchronization side effect. PR #2 remains at the previously presented `2c2fcf5` commit.

## Selection correction awaiting integration

A separate `fix/structural-selection-retention` branch preserves selected text when an unchanged block is duplicated or moved, including when a native text field is recreated with a new Markdown projection. Two intermediate corrections failed native QA. The final correction also handles actual last-block duplication, which appends separators, and remaps selection when the existing native frame rebases. Final local verification passes 662 Swift Testing headlines (four optional skips), 58 XCTest and unsigned iPhoneOS Release. Fresh official Xcode MCP native verification preserves the full “Foo” highlight after the actual last-block duplication, with unchanged source hashes and no provider request. [Evidence](qa-selection-relocation-20261012/README.md).

The regular Markdown export produces the exact 43-byte Unicode witness. The system Files save dialog did not expose actionable hierarchy controls, so save/import/reopen acceptance remains incomplete. [Partial evidence](qa-markdown-files-20261012/README.md).

## Production PDF integration awaiting integration

A separate `fix/production-semantic-pdf` branch makes the semantic tagged renderer the regular shared route for PDF preview and page/manuscript export. Native regular-launch preview and actual system-share PDF pass with unchanged original source. All 124 export tests pass with the 95,744-word/three-profile opt-in enabled. The unused WebKit PDF class is preserved in Research and removed from the native target. Reader compatibility limits and final Release evidence are recorded in [production PDF QA](qa-production-semantic-pdf-20261012/README.md); tagged output does not certify PDF/UA. Native long/media/theme, accessible-reader and full R13 acceptance remain open.

## Resizability investigation

Regular native phone verification found that rotating the focused editor loses the writing surface to the file-browser root. A foreground-presentation experiment failed and was reverted. A fresh iPad pass reproduced the same failure with the scene-configuration hypothesis, so that change was reverted. The independent writing-bar API modernization remains; it does not fix rotation. [Investigation and retained failures](qa-resizability-20261012/README.md). R10 remains open.

## Library presentation lifetime candidate

A separate `fix/library-presentation-lifetime` candidate retains the library hosting controller independently of the decorative document-browser background, using only the anchor view’s own window. Final unsigned Release compilation passes. Fresh ordinary iPad verification preserves the focused editor through portrait/landscape/portrait, supports close/reopen and opens a second library window with the same scope. Exact complete library bytes remain unchanged. Phone verification also retains the correct editor through rotation and background/foreground, with exact original Unicode source and complete library bytes. Phone rotation still dismisses the keyboard and input focus, and landscape body content is partly clipped. The second-window Markdown creation action did not open a creation UI; pending-typing lifecycle acceptance remains separate. [Evidence and limits](qa-library-lifetime-20261012/README.md). Full R10 and R04 remain open.

## Release gates still open

The actual Apple App ID `com.mobilebox.Skriptum` in team `SP73Z8JWXM` was read on 11 October: PCC enabled, iCloud/CloudKit and Push Notifications disabled. Existing cached profiles lack the latter capabilities. The specific action-time confirmation to enable those capabilities, assign `iCloud.com.mobilebox.Skriptum` and renew signing profiles is pending. Source entitlement declarations and unsigned compilation do not substitute for this grant.

After the grant: renew profiles, produce a signed distribution archive, verify its actual entitlements and runtime flags, upload, wait for processing, complete compliance, assign the internal group and verify the actual build shown there. The current candidate has not passed those delivery gates; previously delivered build 2 is a separate artifact.

Actual iCloud collaboration between participants, provider/device/region acceptance, twenty integrated grammar/style language witnesses and the remaining accessibility/export checks retain their documented limits. No current-source device or TestFlight claim follows from local unit tests.

## Evidence map

- [Requirements](REQUIREMENTS.md), [professional writing scope](PROFESSIONAL_WRITING_PLAN.md)
- [Acceptance history](ACCEPTANCE_STATUS_20261010.md), [release preflight](releases/build3/PREFLIGHT.md)
- [WWDC improvements](WWDC_WRITING_IMPROVEMENTS_20261011.md), [project layout](PROJECT_LAYOUT.md)
- [German/English privacy text](legal/README.md), [licenses](licenses/README.md), [Apple submission material](app-store/README.md)
