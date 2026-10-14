# Native grammar engine → application module · 15 October 2026

This unshipped R14 milestone connects the real native engine to Scriptum's Swift quality module. It does not enable a native engine route in the app UI or change delivered iOS build 9 / Mac build 10.

## Behavior implemented

`BundledRuleReviewer` runs lossless, sentence-aware chunks from the existing Markdown projection. A process-wide serial queue executes at most one native driver call across reviewers/windows. Each synchronous Graal driver call creates, configures and tears down its isolate on the same thread, including when configuration/checking fails. The heap budget remains 256 MiB.

Cancellation resumes the waiting Swift task promptly and discards its native result. A call already executing finishes its current section and releases its isolate; a subsequent native call waits for that cleanup. This does not interrupt an individual native rule or guarantee its duration. Failures/cancellation never return partial findings as a successful review.

The own-server client and bundled reviewer now share one response decoder. Engine provenance is chosen by the caller, not response metadata. The local label is `LanguageTool 6.6 · lokal`. All existing UTF-16, Markdown protection, offered-replacement and exact-source/revision checks remain in force. No automatic provider/server fallback was added.

## Integration failure found and fixed

The first real host integration run reached the Chinese tokenizer with blank lines/spaces from masked inline code. The original short Chinese witness had not needed HanLP's `data/dictionary/other/CharType.bin`. Missing native resources caused `ExceptionInInitializerError` to escape the old C boundary. The failed receipt and stderr remain under `initial-missing-HanLP-*`; no successful partial-language run is inferred from it.

The source resource configuration now includes the pinned HanLP JAR's 24 original `data/` files (23,461,950 raw bytes). These are embedded in the native binary and are distinct from the 1,888 external LanguageTool rule/morphology files. `HanLPResources.json` records their unchanged bytes, origin JAR and hashes. Fresh, network-denied agent metadata covers all 29 extended projection witnesses and is retained in `Research/NativeWritingQuality/NativeConfig` for reproducible builds. The C check boundary also catches `LinkageError`, returns an engine failure and lets the caller discard the isolate. A permanent masked-Chinese ABI regression now exercises the data-dependent tokenizer path.

## Fresh verification

- All **53 Swift test functions** in the quality package pass. New tests cover long Unicode/Markdown mapping, source/revision protection, execution off the main thread, later-section failure, unsupported-language refusal, prompt cancellation and serialized cleanup across separate reviewers.
- Both **iOS and native Mac app targets build successfully through Xcode MCP**. They contain the common Swift module; the research driver/library remains excluded.
- Corrected native host library: **149,336,400 bytes**. Corrected iOS-arm64 static archive: **148,793,512 bytes**, compilation successful. The separate external transfer pack is unchanged. These are artifact sizes, not App Store download measurements.
- All five corrected native ABI groups pass with network denied: 29 exact language/range witnesses, 29 correction controls, five long chunks, **23** normal boundary/configuration checks and a separate nine-check heap-exhaustion path.
- The real engine passes through the actual Swift worker, source-preserving Markdown projection and common decoder for **all 29 language witnesses**. It produces 30 findings. **28 offered corrections** pass preparation/admission while preserving appended protected inline code; changed revisions are rejected. The two remaining witness rules do not supply a first replacement to admit. No manuscript is automatically rewritten.
- A real invalid resource-root failure is followed by successful checks on the same serialized worker, verifying cleanup/recovery at the driver boundary. All 1,888 external resource byte hashes and the native library hash are checked before the integration probe runs; its execution has network denied.

Host native peak footprints remain approximately 418–424 MB in these runs. Timings include host conditions and are retained as observations, not product latency promises. No iOS native execution, comprehensive 20-language quality acceptance, App Review approval or new TestFlight delivery is claimed.

`STATE.json` binds current sources, all retained artifacts and compilation results. Native binary/toolchain/data artifacts remain outside Git under `work/native-quality-worker-20261015`. The pinned license inventory is still an upper-bound inventory; resource-specific terms (including HanLP data), corresponding-source/relinking materials and target runtime obligations remain to be completed before shipping.

## Reproduction and next work

Use the pinned Graal Java 17/Gluon toolchain, retained `NativeConfig`, Maven `external-resources` profile and the existing verified external data root. Build host/iOS artifacts using `build-commands.json` / `ios-build-command.json`; link the host dylib with the recorded command. Run `Research/NativeWritingQuality/verify_native.py` first. Then run `verify_reviewer.py` with its `--native-receipt` pointing to that successful native `STATE.json`, plus explicit headers/library/resources/cache/scratch/artifact paths. The verifier builds a temporary Swift package against the actual application quality module. Retained `reviewer-commands.json` records exact local commands. `swift-test-command.json` records the package-test invocation; its final result is retained verbatim in `swift-module-tests.log`.

Remaining work includes signed bundle/framework/source packaging, final license obligations, a verified production language catalog, UI availability/error handling and broader positive/negative linguistic and manuscript cases. R14 remains open; the full R01–R15 scope remains binding.
