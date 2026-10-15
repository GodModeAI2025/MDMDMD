# Native rule-engine feasibility

Isolated research toward R14: evaluate the pinned LanguageTool 6.6 grammar/style engine inside a native iOS library, without an HTTP service. This project is excluded from Scriptum's Xcode target and Swift packages. No native engine is shipped or selected in the app yet.

[Gluon's documented static-library path](https://docs.gluonhq.com/#_native_static_libraries) provides C entry points and iOS targets. The bridge exposes a bounded UTF-8 request/output buffer and returns LanguageTool's original JSON matches. It does not activate remote rules or language-model downloads. The caller must serialize access to an isolate and provide valid buffers. Production distribution/source integration and broader acceptance remain unfinished; shared driver, resource validation, cancellation and error-UI progress is recorded below.

## Current application replacement checkpoint, 15 October 2026

The [actual replacement candidate](../../docs/qa-native-app-replacement-20261015/README.md) now embeds the relocated kit's newly linked framework in current Mac and iOS SDK apps. Both development signatures and all 1,888 resource hashes pass. Apart from re-signing metadata, the embedded framework code/data are unchanged. The actual isolated Mac dialog completes German check → accept → undo, and the ordinary Markdown export retains all 87 witness bytes, including protected code/URL and Unicode. iOS is built/signed, not executed. The technical reconstruction recipe and both failed verification assumptions remain explicit. This advances app replacement/signing, without closing preferred-source/data correspondence, 20-language linguistic acceptance, customer distribution or production activation. The regular iOS19/Mac20 TestFlight builds remain unchanged.

## Current Ukrainian generated-source checkpoint, 15 October 2026

The [full Ukrainian source expansion](../../docs/qa-native-ukrainian-generated-20261015/REPORT.md) reproduces all **6,699,678** synthesis entries, **7,474** synthesis tags and **3,472,529** spelling words. Five verifier tests and eight decoder controls pass. The general dictionary has **9,195** additional binary rows and **404** additional tags, all marked `:obsc`; the expected vocabulary source and original spelling-frequency inputs are absent. The source remains `6.6.0-SNAPSHOT`, and the original release generator version is unproven. This closes the complete synthesis-content and spelling-word comparisons, not binary release reproduction, preferred-source completion, distribution approval or R14. Replay commands, source hashes and small receipts are retained; full dictionaries stay outside Git.

## Current Irish and Ukrainian source checkpoint, 15 October 2026

The [Irish source proof](../../docs/qa-native-irish-source-20261015/REPORT.md) binds the actual unmerged IrishFST PR-13 head and reproduces all **2,081,826** unique tagger/synthesis entries, **3,559** tags and five exact tag files. Original Gaelspell **4.8** regenerates the pinned spelling resources and notice byte for byte. Seventeen targeted regressions pass. The exact historical filter selection, Gaelspell's separate maintainer backend, full binary recompilation and distribution obligations remain open.

The [Ukrainian investigation](../../docs/qa-native-ukrainian-source-20261015/REPORT.md) establishes **11 of 17** direct resource mappings and preserves the actual LT JAR's LGPL statement separately from root-data terms. All **47** preselected new lemmas occur with matching stems; replay reproduces the evidence exactly. Five generated resources, the release-version edit, the generator version and full preferred-source/distribution work remain unresolved. This does not authorize redistribution of the complete raw-data archive.

The [new iOS 16 / native Mac 17 release](../../docs/releases/ios16-mac17-quality/README.md) includes the app's incomplete-response and visible-link-text corrections. Xcode-MCP project approval and SDK builds are complete, and both builds are in internal TestFlight. The native grammar framework/resources remain excluded from those delivered apps.

## Previous source-assembly checkpoint, 15 October 2026

[Verified local material assembly](../../docs/qa-native-source-assembly-20261015/REPORT.md) combines the unchanged V3 mirror, later Portuguese original sources/notices, complete tagger/synthesis evidence and all 1,926 portable relink inputs. Twenty-two targeted tool tests pass. The extracted candidate verifies from an independent working directory and reassembles itself without the original checkout into a byte-identical ZIP and manifest. Only small evidence files enter Git; the archives and binary inputs remain under `work/`. Verified duplicate cleanup preserves the original source packages and relink kit.

This closes the fragmented local assembly gap. Irish FST/Gaelspell correspondence, distinct Ukrainian root/derivative rights and source mapping, other data/source and native-SDK correspondence, full preferred-source rebuild, application replacement/signing/installation and distribution terms remain open. No engine production activation, customer-ready distribution, legal approval or completion of R14 is claimed.

## Current quality and relinking checkpoint, 15 October 2026

[Incomplete-response correction](../../docs/qa-native-completeness-20261015/README.md) prevents incomplete rule-engine responses from appearing as completed reviews. Five fixed regression definitions pass after an actual failing run; the complete quality suite passes 68 definitions / 89 cases. The fresh Xcode-MCP compile awaits renewed agent approval; this change is not in the previously archived iOS15 candidate.

[Independent semantic probes](../../docs/qa-native-semantic-probes-20261015/README.md) freeze 88 new texts before execution. Native and JVM match objects agree for all cases, but only six of 21 provisionally valid grammar probes and five of 22 optional concision probes offer the preselected full-sentence correction. A disputed Chinese grammar oracle is excluded before response inspection. This is evidence of remaining coverage gaps, not a 20-language acceptance claim.

[Portable framework relinking](../../docs/qa-native-relink-20261015/README.md) now succeeds for both arm64 platforms from a relocated, hash-verified 1,926-file input kit. Twenty tool tests and all five unchanged native host verification groups pass against the newly relinked Mac framework. iOS is byte-identical to the prior framework; all 16 allocated Mac sections match, with binary metadata differences retained. Full source recompilation, source/distribution completion and application replacement/signing remain separate unfinished work. No production engine activation or upload.

## Current Portuguese synthesis-source checkpoint, 15 October 2026

[Complete synthesis-source proof](../../docs/qa-native-synthesis-source-20261015/README.md) binds all **16,679,668** release form/lemma/POS records and **1,386** tag members to the full editable-source proof. Three new verifier tests, six existing source tests and eleven Java adapter controls pass. This closes the scoped synthesis row/tag comparison; spelling, FSA serialization, other artifacts and final distribution/relinking remain open. No production dependency or delivered build changes.

## Current Portuguese tagger-source checkpoint, 15 October 2026

[Complete editable Portuguese tagger proof](../../docs/qa-native-portuguese-source-20261015/README.md) resolves the stale SCM/root-POM lookup with the actual official v1.2.0 release commit. The three original generators and 204 verified inputs reproduce all **16,679,668** release form/lemma/POS rows exactly, without frequency stripping or Unicode normalization. The older checked-in snapshot binaries are explicitly different and are not substituted for this proof. A bounded streaming/sort verifier, six regressions, original notices and a hash-readback local source-material package are retained. Synthesis/spelling, other data artifacts, native relinking and complete distribution/linguistic acceptance remain open. No production dependency or upload is changed.

## Latest application-runtime checkpoint, 15 October 2026

Further [data/source-material preparation](../../docs/qa-native-data-release-20261015/README.md) adds complete Catalan/Valencia tagger-row correspondence, explicit Irish/Ukrainian resource gaps, 35 original notices, a 12-artifact review matrix and a hash-verified local source-material mirror. Eighteen focused tool regressions pass. Distinct Ukrainian root-data and derivative-distribution terms remain explicit; the mirror is not approved for customer redistribution. This work does not activate or upload the native engine.

Further [upstream linguistic evidence](../../docs/qa-native-linguistic-20261015/README.md) now preserves 276 preselected positive/negative cases, complete native/JVM response parity, 122 safe corrections and one explicitly manual-only suggestion. Two overlapping Irish XML IDs remain visible rather than being silently rewritten. All 62 quality-module tests, nine evidence-tool regressions and the regular iOS Xcode MCP build pass. The actual selected grammar/style classifications cover 15/four languages respectively, so this bounded corpus does not close the 20+ language quality requirement. Native dialog approval, complete source/distribution work and production activation remain open.

[Shared runtime and actual app candidates](../../docs/qa-native-app-runtime-20261015/README.md): the app module now validates the pinned manifest and every resource before constructing its native driver. The common Textprüfung flow connects this driver to source/revision-bound corrections, explicit language choice and matching Apple spelling without duplicate system grammar/style results. All 59 quality tests, all 29 unchanged native host witnesses and both regular Xcode MCP builds pass. A per-read autorelease pool lowers the measured same-corpus host peak from 759 MB to 418 MB. Actual local Mac and iOS-arm64 apps also compile/link, embed all 1,888 verified resource files and pass development-signature checks. The [actual native Mac dialog](../../docs/qa-native-dialog-20261015/README.md) now passes German/English correction and exact AX-source Undo checks after successful Xcode approval and source-registration refresh at the same candidate path. iOS execution is still unverified. Broader quality, source/relinking/distribution completion and production dependency activation remain open; no new TestFlight upload or iOS execution is claimed.

## Previous source-binding checkpoint, 15 October 2026

[Pinned runtime and dictionary sources](../../docs/qa-native-source-bindings-20261015/README.md): source archives now bind the installed Graal/SVM commit, the Java base and the iOS static-SDK version to public upstream commits. The actual bundled Java source archive and four omitted runtime-root notices are retained. The classifier recognizes `LICENCES` and rejects source-code/images/archives/templates from plain-text notice output; existing output directories cannot be overwritten. Thirteen regression tests pass. Complete French and Spanish word/lemma/tag source comparisons pass for 666,726 and 3,689,171 records after the declared frequency suffix is removed; frequency values and FSA serialization are not claimed equal. Ten other data-source reviews, native binary correspondence, final relinking/distribution materials and production integration remain open. No engine app route or new build is activated.

## Previous distribution checkpoint, 15 October 2026

[Framework packaging, full iOS link and source materials](../../docs/qa-native-distribution-20261015/README.md): separate ad-hoc signed iOS/macOS arm64 framework candidates and an XCFramework now link with a verified raw resource bundle. The unavailable SDK pin is corrected to the installed Graal-generation default; the framework excludes the generated application delegate/bootstrap and uses its own typed iOS compatibility layer. All five native groups and the actual Swift correction pipeline pass via direct framework module import. Both Swift target consumers link and the real Mac app builds through Xcode MCP. The Mac target explicitly matches macOS 27's Apple-silicon hardware. Sources for 132 Maven artifacts are retained; two metadata-only and 12 linguistic-data artifacts have no standard sources JAR. License classification excludes code, correcting the older 96-sequence inventory to 94 legal sequences. Final SDK/data/source/relinking obligations, production availability and UI integration remain open; no engine route or new TestFlight build is activated.

## Previous application-module milestone, 15 October 2026

[Native worker and decoder integration evidence](../../docs/qa-native-worker-20261015/README.md): a process-wide serial Swift worker supports prompt cancellation and isolates every native call's cleanup. The real native host engine passes through the actual quality module, Markdown projection and source/revision-bound correction admission for all 29 synthetic witnesses. The integration probe uncovered and fixed a missing HanLP Chinese tokenizer resource path; the 24 original HanLP data files and fresh pinned native metadata are now included. All five native groups, 53 Swift quality tests, both Xcode MCP app builds and corrected iOS static compilation pass. The native iOS archive is now about 149 MB. The driver is still excluded from production targets, and native UI availability, final framework/resource/source/license packaging, iOS execution and broader language acceptance remain open. This does not close R14 or change TestFlight delivery.

## Previous resource-pack milestone, 15 October 2026

[External-resource build and evidence](../../docs/qa-native-resource-pack-20261015/README.md): the native iOS archive shrinks from about 476 MB to 138 MB with 1,888 byte-identical resource files in a separate 155-MB compressed transfer package. All native parity/correction/long-text and expanded boundary checks pass. Both Irish duplicate files stay on the original classpath. The new `external-resources` Maven profile requires a verified local resource root via `scriptum_quality_set_resource_root`; `verify_native.py --resources` supplies it. The packer and license inventory have permanent regression tests. Declared license metadata for all 146 classpath artifacts and original notice bytes are retained; distribution/source obligations remain unfinished. No App Store download-size or app-integration claim is made. Production integration will use verified raw resources in the signed bundle and a separate native framework, avoiding a duplicate ZIP/extracted cache.

## Current milestone, 15 October 2026

[Fresh native C-ABI and memory evidence](../../docs/qa-native-rule-engine-20261015/README.md): all 29 separate non-dictionary parity witnesses and exact UTF-16 ranges pass; 29 correction controls and five long chunks pass. Sixteen buffer/input/range boundary checks and an explicit no-partial-output heap-exhaustion check pass. Per-record isolate teardown reduces accumulation; 256 MiB heap succeeds while 128/192 MiB report a controlled failure for German. Peak process footprint remains about 425 MB, and the iOS static archive remains about 476 MB. The updated iOS library compiles, but app integration, production distribution/licensing, broader quality coverage and iOS runtime evidence remain open. Use `verify_native.py` to reproduce the recorded native checks.

## Verified experiment, 14 October 2026

- Maven Java compilation succeeds with LanguageTool 6.6 and the declared Graal API dependency.
- The full library processes all 29 existing synthetic language examples directly with `sandbox-exec` denying network operations. Every original expected rule ID remains present.
- This is a macOS Java-VM run with the Native Image agent. It is neither an iOS runtime test nor proof of comprehensive grammar/style coverage in 20+ languages.
- The Java-23/GluonFX-1.0.29 iOS compile fails before rule execution because the CAP cache lacks `JNI_VERSION_19`. No object/library is claimed.
- The documented Apple-Silicon Java-17 toolchain repeats all 29 offline checks with fresh matching metadata and passes the JNI-cache stage. A targeted trace identifies Netty's `ChannelInitializer` as the cause of a logger initialization conflict. Delaying Netty initialization to runtime removes that failure.
- Native analysis initially failed on `JapaneseImperialCalendar`. A research substitution now makes `TestHackHelper.isJUnitTest()` false: the unsupported calendar was reached only by the JUnit frozen-clock branch. Production date rules remain active. The ordinary JVM entry rejects a JUnit context.
- Fresh Java-17 iOS arm64 static-library compilation succeeds with `--no-fallback`. This is compile evidence, not an iOS execution result.
- A native macOS C-ABI probe exposed missing dictionary resources, then Hunspell's requirement for a file URL. Research now excludes dictionary-based spelling rules, while the app retains Apple spelling checks. Full grammar/style multilingual execution is still unproven.
- The latest native corpus stops at gl-ES because the original full-engine fixture expects HUNSPELL_RULE. The fixture needs a separately documented grammar/style scope; no corpus success is claimed. Peak footprint until failure was 1,154,860,664 bytes. The native prototype remains excluded from the application.

The source corpus is the permanent test fixture under `Modules/SkriptumWritingQuality/Tests/SkriptumWritingQualityTests/Fixtures`. The large SDK/runtime, downloaded dependencies, generated classes and agent output belong under the task's `work/native-quality-aot-20261014`, outside Git. Initial generated output was hash-checked and preserved there before cleaning this research folder.

## Reproduction

Pass absolute task-specific locations using Maven properties:

```text
-Dmaven.repo.local=<work>/m2
-Dscriptum.buildDirectory=<work>/target
-Dscriptum.graalvmHome=<verified-graal-home>
-Dscriptum.agentDirectory=<matching-agent-config>
```

Build Java first with `package dependency:build-classpath`. Generate matching Native Image agent metadata by running `NativeWritingQuality --corpus <synthetic-fixture>` under the selected Graal Java runtime, with network denied. For GluonFX 1.0.29, run `gluonfx:compile gluonfx:staticlib` explicitly: the static-library goal alone only attempts to archive an existing object.

## License boundary

No production dependency or MIT acknowledgement has changed. LanguageTool and its components carry the licenses documented in [the existing engine setup](../../Server/WritingQuality/README.md); native integration must retain the actual license texts and resolve distribution requirements before release. The research POM is not evidence of approval or of an installed iOS feature.
