# External native grammar resources · 15 October 2026

This unshipped R14 milestone separates the native engine from its rule/morphology data. It does not change the delivered iOS build 9 or Mac build 10.

## What changed

A reproducible packer preserves 1,888 rule/morphology resource files byte-for-byte, records their original JARs and SHA256 values, and builds a deterministic ZIP transfer artifact. No language, grammar rule or morphology dictionary was removed. Two differing Irish `filter-archaic.txt` files remain in their original classpath; their multiplicity and different bytes are checked explicitly. Unexpected conflicting resources cause packaging to fail.

A native data broker reads these files through a configured local root, preserving metadata/resource-bundle lookup on the original classpath. Missing packed files do not silently fall back to old embedded rule data. Traversal and symlink paths are rejected. Resource-root configuration is bounded and refused after a review has started.

The `external-resources` Maven profile excludes the packed paths from the native image. It retains the known Irish duplicate path and the other original metadata resources. The default full-resource research profile remains available.

## Size and packaging scope

- Previous iOS static archive: **476,405,520 bytes**.
- New iOS static archive: **138,060,128 bytes**.
- Separate compressed data package: **155,433,272 bytes**.
- Static archive plus transfer ZIP: **293,493,400 bytes**.
- Uncompressed external data: **337,383,291 bytes**.

This proves a much smaller native binary and a separable data layer. It is **not an App Store download-size measurement**: App Store compression also applies to embedded resources. Bundling both the transfer ZIP and an extracted runtime copy would duplicate data and can increase installed storage. Production decision: copy verified raw resources into the signed bundle and link the native engine as a separate framework. Do not bundle the transfer ZIP plus an extracted runtime cache. This avoids duplicate model storage and retains a separable library/data boundary. Apple asset delivery can be evaluated later; it is not a prerequisite for the first integrated offline route. The selected production layout is not yet implemented.

## Verification

All five native groups pass with network denied and the unchanged pinned source corpus:

- 29 exact rule/UTF-16 witnesses across distinct languages.
- 29 correction controls.
- Five long text chunks near the app chunk boundary.
- 22 ABI/buffer/configuration checks, including invalid and changed resource roots.
- A separate nine-check configuration/heap-exhaustion path with untouched buffers and isolate teardown.

Ten additional JVM broker checks cover exact Unicode bytes, missing files, stream/URL traversal and symlink rejection, and the two original Irish classpath variants. Five permanent Python tests cover exact/reproducible packaging, traversal, conflicts, the Irish exception and classified-JAR parent-license resolution.

The external-resource native Mac library and iOS-arm64 static archive both compile. Final long-chunk host peak footprint is about 423 MB. This is not iOS execution, broad linguistic quality acceptance or app integration. Timings in the receipts are host observations, not promised app latency.

`STATE.json` binds native outputs, artifacts and source hashes. `manifest.json` retains every packaged resource hash and both classpath-retained Irish variants. The large ZIP, extracted data, native archives and toolchain stay under `work/native-quality-packed-20261015`, outside Git.

## License evidence and remaining work

[The pinned license inventory](../licenses/native-engine-research-20261015/INVENTORY.json) now resolves direct or parent-POM license declarations for all 146 classpath artifacts. It retains 51 distinct embedded JAR notices plus additional original distribution/JDK notices, for 96 unique notice byte sequences. The original LanguageTool 6.6 distribution hash is checked before retaining its license texts. Multiple declared licenses are preserved without guessing whether they are alternatives or combined obligations.

This is a classpath upper bound, not proof that every artifact is linked. Resource-specific licenses, target static-runtime obligations, corresponding-source/relinking materials and actual distribution terms still require completion. The inventory explicitly does not approve distribution. Current app acknowledgements remain unchanged because the engine is not linked into the app.

Next integration work remains a serialized off-main-thread worker, cancellation/cleanup, truthful native engine labels, source/revision-bound manual correction admission, production resource/source packaging and broader linguistic cases. R14 stays open.

## Reproduction

Run `pack_resources.py --classpath <pinned classpath.txt> --output <fresh directory>`. Compile with the pinned Graal toolchain and Maven profile `-Pexternal-resources`. Link the host probe library using the recorded command, then run `verify_native.py` with `--headers`, `--library-directory`, `--resources <extracted root>` and `--artifacts <output>`. Python packaging tests run with `python3 -B -m unittest discover -s Research/NativeWritingQuality/tests -p test_packaging.py`. The separate broker probe is explicitly JVM-only.

The pinned Graal compiler interprets a colon in a resource pattern as a module delimiter, so this profile uses ordinary capturing parentheses rather than `(?:...)`. The initial failed compiler log is retained; the corrected profile passes both builds.
