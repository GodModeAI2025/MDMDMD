# Native rule-engine feasibility

Isolated research toward R14: evaluate the pinned LanguageTool 6.6 grammar/style engine inside a native iOS library, without an HTTP service. This project is excluded from Scriptum's Xcode target and Swift packages. No native engine is shipped or selected in the app yet.

[Gluon's documented static-library path](https://docs.gluonhq.com/#_native_static_libraries) provides C entry points and iOS targets. The bridge exposes a bounded UTF-8 request/output buffer and returns LanguageTool's original JSON matches. It does not activate remote rules or language-model downloads. The caller must serialize access to an isolate and provide valid buffers. Production lifecycle, cancellation, caching, error presentation and licensing integration remain unfinished.

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
