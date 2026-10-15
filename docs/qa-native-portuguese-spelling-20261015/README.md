# Portuguese spelling source and binary reconstruction — 15 October 2026

All **10,594,989** word/frequency rows match the actual pinned release dictionaries. All three newly serialized `.dict` files are **byte-identical** to their JAR resources, and all three original `.info` inputs match exactly. This covers **one language with three orthographic variants**, not three languages.

| Variant | Complete word/frequency rows | Dictionary bytes | SHA-256 of rebuilt and original dictionary |
|---|---:|---:|---|
| pt-BR | 7,735,255 | 2,293,645 | `0c0f4d2502753ad3e7d00d1749715a89a72c70cf78a10327f3157289b455eeb3` |
| pt-PT-45 | 1,428,315 | 702,614 | `8badf728ad0d8b4e6c2feeadc2191372023e2c2113877d9ce1485d05d69e0006` |
| pt-PT-90 | 1,431,419 | 700,866 | `767c003ea80ddc10711bee446e36c7746e3856a9f8362e72ac8883485bc9d61e` |

## Sources and actual execution

[SOURCE_PINS.json](SOURCE_PINS.json) records the Portuguese v1.2.0 release commit, original dictionary-tools submodule gitlink, Hunspell v1.7.2 commit and LanguageTool v6.6 source blobs. Git archives omit submodule contents: the release tree identifies dictionary-tools `5c661e762e50115b6784fa441a039e2950261be5`. Original notices and the relevant original build sources are preserved under `upstream/` and indexed in [UPSTREAM_MATERIALS.json](UPSTREAM_MATERIALS.json).

[run.py](run.py) records the actual complete generation. It binds unchanged archive inputs and the pinned Java classpath, uses the unmodified local Hunspell unmunch program, losslessly converts Latin-1 main words to UTF-8, invokes the original LanguageTool WordTokenizer and preserves untokenized compounds. Original frequency lookup uses the first tab field, retains the complete word line, keeps the last duplicate frequency and applies integer `f * 26 // 256` (actual maximum 221). It does not decode literal XML entities. [generation-COMPARISON.json](generation-COMPARISON.json) compares every word and frequency row, with no source-only or binary-only entries.

[rebuild.py](rebuild.py) consumes the **source-generated** frequency rows, validates their recorded hashes, encodes the original `_` plus A–Z frequency suffix and sorts unsigned bytes. The pinned Morfologik 2.1.9 FSABuilder and default CFSA2 serializer create the new binaries. [fsa-REBUILD.json](fsa-REBUILD.json) records exact binary equality. The 24 generation and six serialization commands, exit results and stderr/stdout are retained. Generator/decoder/serializer subprocesses run with network denied through sandbox-exec. The actual input manifests confirm unchanged inputs during each run.

The generation helper was subsequently extended only with `write_fsa_records` for the serialization phase. Its earlier revision is retained as `portuguese_spelling_source-generation.py`: it was recovered afterward by removing that appended function and checked against the actual generation input hash `b5a0f78fd50695ba5ad34f2564d5de135b641b02739d3e013c01c7740a99ded4`. It was not a pre-run copied snapshot. The serializer separately binds the final helper revision.

## Failures and focused checks

The initial attempt failed at Brazilian entry 6,184,971 because the reused Ukrainian decoder rejected a tab in an original word. Inspection found **four** Brazilian word records with literal tabs; all are preserved exactly. The Portuguese-specific decoder accepts internal tabs/underscores and still rejects malformed UTF-8, NUL/CR/LF, invalid frequency and oversized records. The older Ukrainian decoder is unchanged. The actual failed first attempt, inspection and red/green tab regression are retained; no cleaning or skipping of these source words was used to obtain equality.

Nine permanent Python tests pass, including changed input, symlink/traversal/alias, Latin-1, Unicode, frequency, overwrite and exact FSA encoding controls. The Portuguese decoder and FSA adapter have their own passing self-checks. Source-mode Java inspection initially failed package-private class loading; ordinary compilation resolved it. The first FSA adapter used the wrong `FSA.read(Path)` API and did not compile; the final version uses InputStream and passes its roundtrip, deterministic serialization and invalid-input controls. Its initial source remains preserved; no separate initial compiler-stderr file was saved.

## Retention and replay

[PACKAGE.json](PACKAGE.json) and [MANIFEST.json](MANIFEST.json) describe a verified local source-material ZIP with original source archives, published Morfologik sources, unchanged notices, tools and actual execution receipts. Large material files remain outside Git under `work/native-quality-portuguese-spelling-20261015/source-material-package/`. This is a source-material mirror, not a hermetic toolchain: recorded Java 17, clang and the pinned runtime classpath are still required. The original release workflow used an unpinned Hunspell branch and LT 6.5-SNAPSHOT; our recorded compatible toolchain reproduces the bytes but does not establish historical CI-tool identity.

[CLEANUP.json](CLEANUP.json) records lossless compression/deduplication of owned large generated text intermediates. Every retained gzip was fully reread and matched to its original size and SHA-256 before unlinking the uncompressed duplicate. Restore a row file by decompressing its recorded retainedGzip to its originalPath and checking bytes/hash. Replay scripts intentionally require fresh output directories; use a separate fresh work directory and adapt the recorded absolute paths. Original archives, source files, rebuilt dictionaries, logs and prior checkpoints remain intact.

No app source, dependency, target, provider, ordinary Release activation, upload or Store submission changes here. iOS 19 / Mac 20 internal delivery is a separate existing checkpoint. Complete Portuguese tagger/synthesis serialization, other languages, linguistic acceptance and customer distribution remain open. Binary/source identity alone is no judgment that every original spelling entry is linguistically correct.
