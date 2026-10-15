# Native grammar data and source-material package · 15 October 2026

This checkpoint advances the source and distribution preparation for R14. It does not activate the engine, upload an app, approve redistribution of the source mirror or close the full R01–R15 goal.

## New evidence

| Input | Verified scope | Still outside that scope |
|---|---|---|
| Irish 0.02, commit `2a127b3d` | Seven of 15 complete JAR resources match the release archive, including both POS/synthesis binaries | Eight same-path members absent; original Irish FST/Gaelspell binding and resource-specific distribution completion |
| Catalan 2.26, commit `4e2dbc16` | Six of 14 resources directly identical. Complete tagger text matches **1,198,778** standard and **1,271,246** Valencia word/lemma/tag rows | Eight same-path members absent. Editable-root rebuild, frequency values, synthesis and spelling not proved |
| Ukrainian 6.6.0 source candidate, commit `4787f7ac` | Six of 17 resources identical, including original distribution metadata/notices | Eleven same-path members absent; full source/binary mapping and applicable terms still need completion |

The Catalan comparison applies the original documented verb exclusions, expands every source lemma/tag pair, unions/deduplicates Valencia additions and removes only the metadata-declared frequency suffix as BaseTagger does. Both complete comparisons have zero missing rows. The permanent comparison script reproduces the result and records hashes of the actual decoded files. Original source scripts were read, not executed. The complete actual JAR was decoded with the retained own `DumpDictionary.java` under network denial; export commands and logs are included.

The general resource comparator checks every non-META-INF resource of a pinned data-only JAR. It rejects compiled classes, duplicate/escaping archive names and oversized input, follows no source links and never extracts or executes upstream content. An exact result also reproduces the earlier Dutch nine-of-nine and Asturian eight-of-eight results. A missing same-path file is not represented as absence of preferred source. CLI comparisons with such gaps return 1 and retain their reports.

Six resource-comparator regressions, four Catalan-assembly regressions and eight package-builder regressions pass. Their failure cases cover changed bytes, path/identity confusion, malformed source rows, source changes, unapproved input roots, symlinks and overwriting existing evidence. The package-builder tests also produce byte-identical ZIPs from identical inputs and preserve non-UTF-8/CRLF bytes exactly.

## Original source and license distinctions

`SOURCE_REVIEW.json` tracks the current evidence and remaining points separately for all 12 data-only Maven artifacts. It retains their actual binary fingerprints and declared POM terms; all actual pinned artifacts were rehashed. `RETAINED_NOTICES.json` indexes 35 complete original notices/readmes with their archive-member identities and hashes. None were normalized or relabeled.

The [Irish release README](https://github.com/jimregan/languagetool-ga-dicts/blob/2a127b3d079fb3824b89b60d21ae3db1cb348b28/README.md) distinguishes dictionary data, build scripts and the remaining material. The [Catalan Java-distribution notice](https://github.com/softcatala/catalan-dict-tools/blob/4e2dbc16dd5fbe2009ac4f523f9a2cc9d4d9a29a/resultats/java-lt/LICENSE) explicitly records dual terms. These original notices remain alongside their complete license texts, not replaced by a generic MIT entry.

The [Ukrainian root README](https://github.com/brown-uk/dict_uk/blob/4787f7acbed642584697ff7ccd772fafa5de1f31/README.md) labels root dictionary data CC BY-NC-SA 4.0 and software GPL3+, and expressly notes different derivative-project licenses. The [Morfologik distribution README](https://github.com/brown-uk/dict_uk/blob/4787f7acbed642584697ff7ccd772fafa5de1f31/distr/morfologik-ukrainian/README.md) labels the LT artifact LGPL2.1+. Both statements are preserved; the source tree is not collapsed into a blanket LGPL assertion. The source-material mirror is internal preparation and is **not approved for app/customer redistribution**.

The actual Portuguese source repository is [portuguese-pos-dict](https://github.com/languagetool-org/portuguese-pos-dict), correcting the stale POM URL. Its root `pom.xml` history is empty; no release pin was invented. Belarusian and Crimean Tatar source binding remains open. Earlier French, Spanish, English, German, Dutch and Asturian receipts retain their own precise scopes.

## Verified local package

`Research/NativeWritingQuality/bundle_verified_materials.py` packages only explicitly listed, hash-pinned regular files under caller-approved roots. It rejects path/case aliases and source symlinks, never overwrites an existing output, verifies bytes while streaming, and reads every member back before publishing its final ZIP name and receipt. It performs no downloads, compilation, installation or publication. Integrity is deliberately separate from completeness or licensing approval.

The final `SOURCE_PACKAGE.json` and `SOURCE_PACKAGE_MANIFEST.json` identify the actual local package under `work/native-quality-data-review-20261015/source-materials-v3-release-candidate/`. It retains the previous verified V2 mirror (including 132 Maven source archives and pinned runtime source material), seven additional dictionary archives, native integration sources, the current component review and original notices. Large archives remain outside Git. Earlier V3 snapshots remain intermediate evidence. The current package additionally verifies that every indexed original notice is present; an initial README-name filter omission was caught and corrected before any release integration. The current manifest makes the Ukrainian notice distinction explicit.

Native SDK/modified-host source correspondence, remaining data-source/term review, relinking/installation instructions and final application terms remain open. Source-package integrity does not establish these conditions. The regular app project and its Settings.bundle remain unchanged because this dependency is still unshipped. This checkpoint requires no new app build; the previous actual iOS/Mac build and TestFlight receipts keep their existing scopes. App Store Connect login and the separate candidate's Xcode confirmation remain pending; neither was retried or bypassed here.
