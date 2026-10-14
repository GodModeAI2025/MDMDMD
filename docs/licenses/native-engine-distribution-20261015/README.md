# Native engine distribution materials · 15 October 2026

These are preparation materials for the unshipped native grammar engine. They do not change the delivered app's Settings.bundle or approve distribution.

- `inventory/INVENTORY.json` resolves declared POM licenses for all 146 pinned classpath artifacts and retains 94 distinct original legal byte sequences, including distribution/JDK notices. This remains a classpath upper bound, not a native reachability result.
- `MATERIALS.json` records 132 published Maven sources JARs, their binary/version coordinates, SHA256 values and verified published SHA1 checksums. Those source archives remain outside Git in the task's work directory. The ZIP receipt is `SOURCE_PACKAGE.json`.
- `source-notices/` retains 99 exact original legal/documentation texts, including language/resource READMEs that were missing from the earlier license-only selection. Original encodings, line endings and whitespace remain unchanged.
- The 14 missing standard Maven sources coordinates comprise two metadata-only artifacts and 12 linguistic-data artifacts. Their contents, declared SCM and licenses are retained in the [source-gap report](../../qa-native-distribution-20261015/SOURCE_GAPS.json). A missing Maven sources JAR is not proof that upstream source data is unavailable.

The earlier 96-sequence inventory accidentally selected two compiled `CopyingImageHeapProvider` classes by filename. The first expanded README scan also selected `JvmThreadMetrics.class` because its name contains `README` across a word boundary. The shared classifier now excludes code suffixes and has a permanent regression. Earlier artifacts remain unchanged as historical evidence; corrected classification is recorded separately. Compiled code is never presented as license text by this material set.

The pinned OpenRegex 1.1.1 release license is retained in the [distribution evidence](../../qa-native-distribution-20261015/OpenRegex-1.1.1-LICENSE.txt). Its 14 Java source files match the published sources JAR byte-for-byte at upstream commit `3a54ed670449ac75d54d65d318c0814e39ff7ba9`. This resolves the vague Maven LGPL declaration to the original release's LGPL v3 text; it does not establish that the final application distribution meets its conditions. [Original release license](https://github.com/knowitall/openregex/blob/v1.1.1/LICENSE).

Resource-specific preferred sources/terms, complete native runtime SDK source/notices, relinking/installation materials and the final application terms still require completion. The downloaded iOS SDK ZIP contains static archives without accompanying source/license files; the older JDK notice inventory alone does not cover it. The own iOS compatibility source has a separate MIT license copied into the framework candidate. No third-party code is relicensed by that notice.

No engine UI route is enabled and no new TestFlight upload is made by this work. The [distribution checkpoint](../../qa-native-distribution-20261015/README.md) records the actual compilation, packaging and host execution scopes.
