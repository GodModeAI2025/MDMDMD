# Native engine experiment — 2026-10-14

[Research source and exact scope](../../Research/NativeWritingQuality/README.md).

The full LanguageTool 6.6 library compiled and retained expected rule IDs across all 29 existing synthetic language examples in an in-process run with network denied. The Java-23 native iOS attempt is terminal and unsuccessful: missing CAP-cache `JNI_VERSION_19`. The detailed compiler diagnostic is retained here.

The measured 1,879,738,624-byte peak includes the macOS Java VM and tracing agent. It is not an iOS memory measurement. Recorded timings likewise include instrumentation and cold initialization; no app performance promise is derived from them.

The documented Java-17 toolchain also processes all 29 offline examples and generates its own matching metadata. It passes the missing-JNI-value stage. Its first analysis fails because Netty's `ChannelInitializer` initializes runtime-only SLF4J classes during the build. The targeted initialization trace preserves this cause. Delaying Netty initialization to runtime resolves that stage; the next failure is unsupported `java.util.JapaneseImperialCalendar`, reached through LanguageTool's date filter. The generated JDK-dependent fallback is not an iOS library. The research configuration now explicitly forbids fallback images.

No native library, iOS C-ABI execution, live device behavior, comprehensive 20-language grammar/style coverage, app integration or upload is claimed. Existing TestFlight/App Review Build 8 is a separate artifact.
