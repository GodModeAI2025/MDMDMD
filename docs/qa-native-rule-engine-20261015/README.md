# Native local writing-quality milestone · 15 October 2026

This is an isolated native C-ABI research milestone toward R14. It is **not linked into Scriptum**, does not change the delivered iOS build 9 or Mac build 10, and does not close integrated 20-language grammar/style acceptance.

## Fresh execution evidence

The native macOS library, called from Swift with all network operations denied externally, passes:

- 29 distinct language witnesses. Rule IDs and exact UTF-16 ranges match the original pinned LanguageTool 6.6 responses. Every returned range is bounded by the unchanged input.
- 29 correction controls: the original witness rule disappears after its first suggested correction. Polish uses a specific comma control and Russian uses a valid calendar-date control because those responses provide no replacement. Other rules may remain; these controls do not certify idiomatic prose.
- Five repeated synthetic prose chunks near the app's 16,384-UTF16 chunk boundary: Arabic, German, English, French and Dutch. All original witness rules/ranges remain and every returned range is bounded. These are stress smoke checks, not natural-manuscript benchmarks.
- Sixteen native ABI checks, including malformed UTF-8, embedded NUL, null pointers, oversized arguments, invalid output capacities, no partial output, buffer canaries, unchanged input and the exact UTF-16 range behind an emoji.
- A separate 128-MiB heap-exhaustion case returns `-5` with unchanged input/output buffers, then destroys the isolate. The Swift harness reports ordinary structured errors instead of trapping.

The full reproducible run is in `STATE.json`, with actual responses, stderr, build logs and exact commands beside it. All five verification groups pass. Both the updated macOS native library and iOS-arm64 static library compile using the existing pinned Gluon/Graal toolchain and offline Maven repository. iOS compilation is not iOS execution evidence.

## Corpus integrity

The original full-engine fixture remains byte-identical, SHA256 `4c22a241e367f227cc19fb6dcc523cb9429d5298da77178653170129d042438b`. A separate research parity corpus excludes only its two Galician `HUNSPELL_RULE` expectations, because this native component deliberately does not duplicate Apple's dictionary spelling implementation. The Galician non-dictionary typography witness remains required. Other lexical/grammar/style/typography rules are retained. The existing application tests were not weakened.

These small multilingual witnesses establish native execution compatibility. They do not prove comprehensive grammar and style quality in every language, equal capabilities across languages, or a shipping feature.

## Memory and lifecycle

A single isolate across all languages measured 1,818,724,512 bytes peak footprint. Releasing the isolate after each record measured 459,703,400 bytes. A configurable native heap budget now rejects invalid budgets and changes after reviewing starts. Under a 256-MiB heap budget, the final parity run peaks at 418,235,496 bytes; the five long chunks peak at 425,378,896 bytes. The heap is only part of process memory; it must not be described as a 256-MiB total-memory guarantee.

128 and 192 MiB fail on the small German witness with the explicit `-5` error; these failures are retained. No degraded rule subset or silent fallback was used to obtain the passing 256-MiB result. Timings vary between host runs and are not iOS performance promises.

## Remaining integration work

1. Reduce/distribute the large resource payload: the iOS static archive is about 476 MB. Resource analysis separates about 74 MB of dictionary-spelling assets from roughly 341 MB of matched LanguageTool resources overall. Removing resources requires fresh language/range/correction verification; grammar morphology dictionaries must remain available.
2. Complete actual dependency/license and relinking/distribution requirements before adding a production dependency. Existing app acknowledgements remain accurate for the currently shipped app.
3. Add a serialized off-main-thread native worker with bounded chunk/output mapping, cancellation and guaranteed isolate cleanup. Keep source/revision/Markdown protection and manual correction admission. A native memory error must remain visible, not become a clean-review result.
4. Integrate language selection and truthful engine labels, then validate the actual app route. Test representative grammar/style corpora beyond these one-witness smoke checks. R14 stays open.

## Reproduction

Compile the research POM with the recorded pinned Java-17 runtime, matching native-image metadata, and `gluonfx:compile gluonfx:staticlib` for iOS. Generated artifacts stay under the task's `work/native-quality-aot-20261015`, outside Git. The recorded native link command creates the host-only shared library used by the harness.

Run `Research/NativeWritingQuality/verify_native.py` with `--headers` pointing to the generated host header directory, `--library-directory` to the host dylib directory, and `--artifacts` to a separate output directory. It compiles the two Swift probes, verifies the original fixture hash, executes all five groups with network denied, and writes a hash-bound result receipt.

Upstream technical reference: [Gluon native-library documentation](https://docs.gluonhq.com/). Its current page identifies itself as legacy documentation; the actual pinned toolchain builds and execution receipts above are the evidence for this experiment.
