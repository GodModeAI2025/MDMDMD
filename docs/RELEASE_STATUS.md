# Scriptum release status

Updated 2026-10-12. This page distinguishes the development candidate from the delivered TestFlight build. The complete [R01–R15 requirements](REQUIREMENTS.md) remain binding.

## Completed in the current candidate

- Production code is separated from unshipped prototypes in `Research/`; 455 relocated tracked files retain their exact source bytes. QA evidence and licenses remain versioned. GitHub is the code repository, with no workflows.
- The ordinary editor now applies native keystrokes against the displayed syntax frame. The 43-byte Unicode witness survives editing, durable checkpoint and reopening exactly; rejected drafts are preserved separately. [Evidence](qa-input-frame-20261011/REPORT.md).
- Full local verification for the editor change: 655 Swift Testing headlines (four optional skips) and 58 XCTest, plus unsigned Release compilation. Ten signed-archive-verifier regression tests pass.
- The initial white HTML preview capture was taken before load completion; the stable preview renders correctly. The candidate adds loading/error feedback for page and HTML export previews. Official Xcode MCP verifies the loading indicator followed by actual content on first opening and after closing/reopening the regular page preview; the HTML export caller compiles in Release. [Evidence](qa-preview-loading-20261011/README.md).

## Additional export fix awaiting integration

A separate `fix/epub-author-metadata` branch omits invalid empty EPUB creator metadata. All 124 export-test headlines (one optional skip), unsigned Release compilation and six current-renderer EPUBCheck validations pass. Three 24-chapter profiles preserve paragraph/Unicode/table/footnote/TOC counts independently. [Evidence](qa-epub-conformance-20261012/README.md). Actual Apple Books import requires a concrete confirmation after automatic approval rejected its potential library/synchronization side effect. PR #2 remains at the previously presented `2c2fcf5` commit.

## Release gates still open

The actual Apple App ID `com.mobilebox.Skriptum` in team `SP73Z8JWXM` was read on 11 October: PCC enabled, iCloud/CloudKit and Push Notifications disabled. Existing cached profiles lack the latter capabilities. The specific action-time confirmation to enable those capabilities, assign `iCloud.com.mobilebox.Skriptum` and renew signing profiles is pending. Source entitlement declarations and unsigned compilation do not substitute for this grant.

After the grant: renew profiles, produce a signed distribution archive, verify its actual entitlements and runtime flags, upload, wait for processing, complete compliance, assign the internal group and verify the actual build shown there. The current candidate has not passed those delivery gates; previously delivered build 2 is a separate artifact.

Actual iCloud collaboration between participants, provider/device/region acceptance, twenty integrated grammar/style language witnesses and the remaining accessibility/export checks retain their documented limits. No current-source device or TestFlight claim follows from local unit tests.

## Evidence map

- [Requirements](REQUIREMENTS.md), [professional writing scope](PROFESSIONAL_WRITING_PLAN.md)
- [Acceptance history](ACCEPTANCE_STATUS_20261010.md), [release preflight](releases/build3/PREFLIGHT.md)
- [WWDC improvements](WWDC_WRITING_IMPROVEMENTS_20261011.md), [project layout](PROJECT_LAYOUT.md)
- [German/English privacy text](legal/README.md), [licenses](licenses/README.md), [Apple submission material](app-store/README.md)
