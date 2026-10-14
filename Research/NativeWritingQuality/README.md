# Native rule-engine feasibility

Isolated research toward R14: run the complete pinned LanguageTool 6.6 rule engine inside a native iOS library, without an HTTP service. This project is excluded from Scriptum's Xcode target and Swift packages. No native engine is shipped or selected in the app yet.

[Gluon's documented static-library path](https://docs.gluonhq.com/#_native_static_libraries) provides C entry points and iOS targets. The bridge exposes a bounded UTF-8 request/output buffer and returns LanguageTool's original JSON matches. It does not activate remote rules or language-model downloads. The caller must serialize access to an isolate and provide valid buffers. Production lifecycle, cancellation, caching, error presentation and licensing integration remain unfinished.

## Verified experiment, 14 October 2026

- Maven Java compilation succeeds with LanguageTool 6.6 and the declared Graal API dependency.
- The full library processes all 29 existing synthetic language examples directly with `sandbox-exec` denying network operations. Every original expected rule ID remains present.
- This is a macOS Java-VM run with the Native Image agent. It is neither an iOS runtime test nor proof of comprehensive grammar/style coverage in 20+ languages.
- The Java-23/GluonFX-1.0.29 iOS compile fails before rule execution because the CAP cache lacks `JNI_VERSION_19`. No object/library is claimed.
- The documented Apple-Silicon Java-17 toolchain repeats all 29 offline checks with fresh matching metadata and passes the JNI-cache stage. A targeted trace identifies Netty's `ChannelInitializer` as the cause of a logger initialization conflict. Delaying Netty initialization to runtime removes that failure.
- The next native analysis fails on unsupported `java.util.JapaneseImperialCalendar`, reached through LanguageTool's `AbstractFutureDateFilter` and `Calendar.Builder`. Its generated fallback requires a JDK and is unusable for this goal. `--no-fallback` is now explicit. Native compilation remains incomplete; do not remove language rules or defer this failure to runtime to claim a successful native engine.

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
