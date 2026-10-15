# Ukrainian generated-resource reconstruction — 2026-10-15
This Git package preserves completed evidence only. No new experiment, build or test was run while packaging. The [retained local reconstruction directory](/Users/markzimmermann/Documents/Codex/2026-10-08/mach/work/native-ukrainian-source-20261015/reconstruction) holds complete source extraction, dependencies and large decoded dictionaries. [REPLAY.md](REPLAY.md) gives the exact commands; [SOURCE_BINDING.json](SOURCE_BINDING.json), [LOCAL_ARTIFACTS.json](LOCAL_ARTIFACTS.json) and [QA.json](QA.json) bind the inputs, omitted raw data and copied evidence. Original execution-time QA is preserved unchanged as [LOCAL_QA.json](LOCAL_QA.json).

The pinned preferred-source candidate now reproduces the full synthesis dictionary content and its tag file, and the complete spelling word inventory. The general morphological dictionary still contains a distinct binary-only segment, and spelling frequency inputs remain absent. This is a bounded content reconstruction, not proof of the original release build or a distribution clearance.

## Inputs and configuration

- Source: `8eb833b901bb77798d6f37e213880db10c462c87`, retained as [release-period-last-source.tar.gz](/Users/markzimmermann/Documents/Codex/2026-10-08/mach/work/native-ukrainian-source-20261015/release-period-last-source.tar.gz); SHA-256 `cd91fe4fa5bfab44ad12b4338ac7fd532d28c793a5e6fd40c8176bff0073360f`.
- Actual artifact: `morfologik-ukrainian-lt-6.6.0.jar`; SHA-256 `3ff49f9b989e3c50eb8d96f4385906b3562b638607aeeddaffd90939695b66a5`.
- Original source `VERSION` remains exactly `6.6.0-SNAPSHOT\n`; SHA-256 `013c4fab746c32cd70a1adf2e6dd607acf40739b7a33432dc6a62234bb714331`. The published artifact is 6.6.0. `publish.sh` rejects SNAPSHOT; the original release working tree/configuration is not recovered.
- Local reconstruction uses existing Java 17, Groovy 4.0.26, groovy-cli-picocli 4.0.26, picocli 4.7.6, commons-cli 1.4 and SLF4J API/simple 2.0.16. POMs and checksum receipts are retained in the [local dependencies directory](/Users/markzimmermann/Documents/Codex/2026-10-08/mach/work/native-ukrainian-source-20261015/reconstruction/dependencies), `dependency-pom-receipt.json` and `dependency-fetch-receipts.json`. These are an explicit reproduction configuration, not asserted historical release dependencies. The simple logger replaces the root build's declared Logback logging dependency only in this research runner.
- Unmodified upstream Java/Groovy sources were jointly compiled. Declared `VerbReverse` / `VerbReverse --advp` and `Autogen` prerequisites ran before `ExpandAll --mfl --wordlist --time`. Optional visual indentation/statistics outputs were omitted. Source inventories confirm no existing upstream file was modified.
- Maximum heap: **4096 MB**, active processors: **2**. No Gradle/publish execution, global installation, app/device/simulator/portal operation or production dependency change.

## Complete comparisons

| Actual JAR resource | Source-to-binary result | Remaining limitation |
|---|---|---|
| `ukrainian_synth.dict` | **6,699,678** distinct word/lemma/tag rows match; 0 source-only, 0 binary-only | Decoded content equality; original binary generator/version is unproven |
| `ukrainian_synth.dict_tags.txt` | **7,474** tags match; exact bytes under declared byte sorting | Complete tag-file correspondence |
| `ukrainian.dict` | **6,751,606** common rows, 0 source-only, **9,195 binary-only** | All additional rows carry `:obsc`; source segment absent |
| `ukrainian_tags.txt` | 7,994 source tags, 8,398 binary tags; **404 binary-only**, 0 source-only | All additional tags carry `:obsc` |
| `hunspell/uk_UA.dict` | **3,472,529** spelling words match; 0 source-only, 0 binary-only | Binary frequency bins decoded and retained; preferred-source frequencies not reconstructed |

The expansion emits 6,751,618 raw POS rows; the declared unique sort removes 12 duplicates. Synthesis filtering preserves the upstream `:(subst|vulg|obsc|vis)` prefix semantics and produces 6,699,689 rows before deduplication. No expected data was changed to fit observed binary results.

The complete sorted synthesis source and binary content share SHA-256 `ffe1134db34dc4905e74cc2a4b91a967bd117c83145dbd3a2c5d6383563640ed`. Complete sorted spelling word lists share `87ade12b85ce16f7f75d8b4bbb372644083b4accdb36c23d12dc45432922e1b6`.

Authoritative machine-readable results: `comparison-01/GENERATED_RESOURCE_COMPARISON.json` and `spelling-02/SPELLING_WORD_COMPARISON.json`. They retain both comparison directions, exact inputs/hashes, process arguments, limits and unchanged-input checks.

## Exactly two missing source segments

1. **Obscene vocabulary.** `data/dict/vulgar_obsc.lst` is absent from the pinned archive. `src/main/groovy/org/dict_uk/expand/TaggedWordlist.groovy:24` assigns that expected filename the `:obsc` tag. Every one of the 9,195 missing POS rows and all 404 extra general tags have that tag. This strongly identifies the absent vocabulary segment; it does not establish that this exact untracked file was the actual release input. The full difference is retained at [pos-binary-only.tsv](/Users/markzimmermann/Documents/Codex/2026-10-08/mach/work/native-ukrainian-source-20261015/reconstruction/comparison-01/pos-binary-only.tsv), SHA-256 `4721285e8e2c3737d3b9a40f58239ff5ac716b00565290d2b17c88c7aa61caa1`. The file was obtained with `LC_ALL=C /usr/bin/comm -13 source-pos.sorted.tsv binary-pos.sorted.tsv`. Decoding these rows is binary evidence, not a substitute for preferred source.
2. **Spelling frequencies.** `distr/morfologik-ukrainian/build.gradle:193` requires `src/main/data/uk_wordlist.xml`, absent from the archive. The tracked `src/main/groovy/wordlist.groovy:18` reads `all.tagged.freq.txt`, also absent. That script aggregates/lowercases corpus counts and creates the XML; its source corpus/count input and generation context are not recovered. All spelling words match, but their frequency weights cannot be called reconstructed. Full actual word/frequency pairs are retained at [binary-word-frequencies.tsv](/Users/markzimmermann/Documents/Codex/2026-10-08/mach/work/native-ukrainian-source-20261015/reconstruction/spelling-02/binary-word-frequencies.tsv), SHA-256 `40228b8d541423e8f9c0a39fccd1889dfc4021ad37444f8c410a6364fb03f2af`.

Separately, the release's external `ltToolsVersion` remains unspecified by reviewed tracked build configuration (`distr/morfologik-ukrainian/build.gradle:70`). No byte-identical `.dict` rebuild with the original tool version is claimed.

## QA and limits

- Successful `run-02`: compile 2.49 s; reverse 0.77 s; reverse-advp 0.62 s; autogen 1.79 s; full expansion **85.09 s**. All exit 0. `run-01` preserves an earlier runner-classpath failure; adding the explicit compiler classpath fixed the runner without changing upstream sources.
- Python verifier tests: **5 passed**, covering strict Unicode fields, malformed rows, exact synthesis prefix filtering, both difference directions, and empty/equal inputs. Evidence: `verifier-tests.json`, `.stdout`, `.stderr`.
- Final spelling decoder replay `spelling-02`: **2 valid Unicode/frequency boundary cases and 6 malformed cases passed**, then full decode and comparison succeeded. Evidence: `self-test.stdout`, `steps.json` and `SPELLING_WORD_COMPARISON.json` in that directory.
- Final receipt `QA.json` binds current research-code hashes, preserved original inputs and result/log hashes. Large raw outputs are retained locally and already hashed by their individual proofs; no large archives are copied into repository QA.
- The [earlier Ukrainian source report](../qa-native-ukrainian-source-20261015/REPORT.md)'s **11/17** directly source-bound resources and **47/47** lemma probes remain their original narrower measurements. This new full-resource reconstruction adds stronger separate evidence; those old metrics are not relabelled as complete reconstruction.
- The actual derivative JAR's explicit LGPL-2.1-or-later notice remains distinct from the root dictionary's CC BY-NC-SA and software's GPL-3-or-later terms, as documented by the earlier retained primary notices. This experiment does not invent relicensing, settle the two missing source segments, or approve native distribution.

## Replay from retained local dependencies

These commands require the existing pinned archive, isolated dependency directory, Java and decoding dependencies; they do not fetch dependencies. Run from the repository root. Each output directory must be fresh. The example uses unused `run-03`, `comparison-02`, `spelling-03` names; choose other fresh names if they exist.

```sh
cd /Users/markzimmermann/Documents/Codex/2026-10-08/mach/outputs/Skriptum
task_work=/Users/markzimmermann/Documents/Codex/2026-10-08/mach/work
task_uk="$task_work/native-ukrainian-source-20261015/reconstruction"
python3 -B Research/NativeWritingQuality/reconstruct_ukrainian_source.py --work-root "$task_work" --output "$task_uk/run-03" --phase prepare
python3 -B Research/NativeWritingQuality/reconstruct_ukrainian_source.py --work-root "$task_work" --output "$task_uk/run-03" --phase expand
python3 -B Research/NativeWritingQuality/verify_ukrainian_generated.py --work-root "$task_work" --expanded "$task_uk/run-03" --output "$task_uk/comparison-02"
python3 -B Research/NativeWritingQuality/verify_ukrainian_spelling.py --work-root "$task_work" --expanded "$task_uk/run-03" --output "$task_uk/spelling-03"
python3 -B -m unittest discover -s Research/NativeWritingQuality/tests -p test_ukrainian_generated.py -v
```

## Ownership and handoff

Only these five new repository files belong to this task:

- `Research/NativeWritingQuality/reconstruct_ukrainian_source.py`
- `Research/NativeWritingQuality/verify_ukrainian_generated.py`
- `Research/NativeWritingQuality/verify_ukrainian_spelling.py`
- `Research/NativeWritingQuality/UkrainianSpellingRows.java`
- `Research/NativeWritingQuality/tests/test_ukrainian_generated.py`

All complete generated data, source extraction and dependencies remain in the [isolated local reconstruction directory](/Users/markzimmermann/Documents/Codex/2026-10-08/mach/work/native-ukrainian-source-20261015/reconstruction); this Git package copies only small evidence files. Existing `DumpDictionary.java` and `SynthDictionaryRows.java` were reused unchanged. Other current repository modifications belong to parallel work and were not touched. No commit was created. No active process/session handles remain. Research stops at this bounded result.
