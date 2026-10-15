# Native grammar: upstream cases and full-engine parity · 15 October 2026

This is an unshipped R14 integration checkpoint. The native framework is still excluded from the regular production project. No TestFlight upload, native iOS execution or comprehensive linguistic acceptance is established here.

## Frozen selection and independent reference

`UpstreamExamples.json` contains 138 original positive/negative XML-example pairs, 276 cases across 28 languages. Its SHA256 is `5fed9c7c55dfcea52e9ccc2d95c0869c4e1b5dff83fd63dc3a0a56b33944dd90`. The selector chose up to five distinct active rule IDs per language through category round robin before execution. Tamil supplies three eligible pairs. Japanese has no eligible pair under this literal, active, paired-example policy; its existing synthetic engine witness remains separate. This is not a declaration that Japanese is unsupported.

The selection preserves source paths, complete XML fingerprints, original line numbers and UTF-16 markers. It strips only outer XML whitespace, rejects dynamic/entity examples and never resolves external XML entities. A second selection is byte-identical. `UpstreamAnnotations.json` extracts the original correction attributes from exactly these fingerprinted source examples; its independent regeneration is also byte-identical. No failing case was removed or rewritten.

`UpstreamProjectionExport.swift` exports the actual application projection. The pinned Java-17 full engine checks those same projected inputs in three batches, using the same external resources with network denied. The native recording harness goes through the real verified application runtime and `BundledRuleReviewer`, recording the submitted text hash and complete raw JSON responses. No payload recording is added to the app.

## Results

| Check | Actual result |
|---|---:|
| Complete native/JVM match-object parity | 276 / 276 |
| Exact originally selected XML rule identity | 274 / 276 |
| Positive detections at their original markers | 138 |
| Negative controls clear of their selected rule and observed overlapping ID | 138 |
| Safe automatic correction, exact outside text, stale-revision refusal and target recheck | 122 |
| Manual-only suggestion with automatic insertion refused | 1 |
| Positive findings without an offered replacement | 15 |
| Application quality-module tests | 62 passed |
| Selector, annotation and evidence-verifier regressions | 9 passed |

Parity compares every field of every match, preserving duplicates and normalizing only JSON keys and match ordering. Both engines explicitly report no incomplete results. It is stronger than merely comparing the expected rule ID, but does not prove that the upstream engine is linguistically correct in every case.

The two XML identity differences are Irish: `CUIG_NUNLENITED` resolves to `CUIG_NOUN` for “cúig páirtí”, and `TRI_UAIRE` resolves to `TRI_UAIR` for “trí uaire ó shin”. Each observed full-engine rule covers the exact original marker and offers the original maintainer correction (“pháirtí” or “huaire”). Both full-engine JVM and native responses agree. Negative controls also reject these observed overlapping IDs. The initial strict run, with 273 successes and three failures, remains intact in `initial-*`; the new report explicitly retains the two identity differences.

The third initial failure was Swedish `APIs` → `API:s`. The engine detects it correctly, but the existing generic URI/Markdown protection refuses automatic insertion. The shared correction dialog now presents this known protected transformation as selectable manual text instead of an Apply button that cannot succeed. Correction admission, source bytes, revision and AST protection remain unchanged. A conservative presentation hint is not an admission authorization: transformations that introduce structural Markdown can still be rejected by the full admission path.

The actual positive finding classifications are 38 grammar, five style, six spelling and 89 other. They cover respectively 15, four, four and 24 languages. These bounded cases do **not** establish grammar and style quality in 20+ languages. XML categories or dictionary counts are not relabeled to manufacture that claim.

The full recording run exits 0 in about 202 seconds on the host, with measured peak memory footprint 421,856,168 bytes. These are host corpus measurements, not per-document latency or iOS memory measurements. SLF4J's no-provider warnings remain in the raw stderr. The regular iOS-arm64 target builds successfully through Xcode MCP; the latest Mac build also compiled these unchanged shared sources in the [Mac UI checkpoint](../qa-mac-paper-20261015/REPORT.md).

## Reproduction and limits

The selectors, source annotation extractor, projection exporter, recording harness, independent verifier and nine boundary/regression tests are under `Research/NativeWritingQuality/`. Full commands, original inputs, raw outputs, framework-aware harness build and iOS build logs are retained here. Large framework/JVM/resource artifacts remain in the task's work directory. Resource validation and framework fingerprints retain their [application-runtime evidence](../qa-native-app-runtime-20261015/README.md).

Run `python3 -m unittest discover -s Research/NativeWritingQuality -p test_upstream_evidence.py -v` for evidence-tool regressions. `verify_upstream_parity.py` accepts the retained corpus, annotations, native JSONL, JVM JSON and projection JSON, with a fresh output path; it refuses an existing output rather than replacing evidence. The native execution command requires the verified local framework and resources. Its output alone is insufficient without the independent JVM comparison.

Actual native-dialog interaction is still pending the separate candidate's own Xcode user confirmation. A fresh open attempt was rejected by automatic approval review before execution because that prerequisite was not confirmed; no workaround was used. App Store Connect still shows its login page. Source/relinking/distribution materials and broader quality acceptance remain required. R01–R15 and the full TestFlight objective remain active.
