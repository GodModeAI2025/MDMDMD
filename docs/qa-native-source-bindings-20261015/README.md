# Native grammar source bindings · 15 October 2026

This checkpoint advances the unshipped R14 grammar engine. It does not enable an app route, upload a build or establish distribution approval.

## Changes and verified inputs

The notice inventory previously searched the runtime's `legal/` directory but omitted four root notices. It now retains `LICENSE.txt`, `LICENSE_NATIVEIMAGE.txt`, `THIRD_PARTY_LICENSE.txt` and `3rd_party_license_llvm-toolchain.txt`, plus exact release metadata and the bundled Java-source archive fingerprint. Missing required release notices fail the inventory. Existing output directories are refused so old evidence cannot be overwritten or mixed with another input set.

Notice matching now recognizes the British `LICENCES` spelling and whole filename tokens. Code, screenshots, archives and copyright-checker templates are excluded from the plain-text notice pool. A scan of the upstream source trees found 26 such false candidates, including three screenshots and a test JAR; their paths remain in the notice index. The corrected runtime/classpath inventory retains 99 distinct legal byte sequences for 146 artifacts and the runtime/distribution inputs. The separate expanded Maven legal/README classification finds 100 text sequences. Earlier inventories remain historical.

The installed release's compiler, SDK and SubstrateVM commit matches the peeled [Gluon 22.1.0.1 release tag](https://github.com/gluonhq/graal/releases/tag/gluon-22.1.0.1-Final): `08e1c57bc6b6de932b0faed2f49b21a1a54a39fe`. Its complete source tarball is retained and hash-checked. The Java base commit resolves to [Labs OpenJDK 17.0.3](https://github.com/graalvm/labs-openjdk-17/commit/05e32d91e144823314b0eda9560de949ef6d40ae). Of 17,633 Java files in the actual bundled `src.zip`, 12,919 match corresponding Mac/share/Unix files in that commit; seven candidates differ, and 4,707 have no such direct match, including generated and Graal sources. The actual bundled `src.zip` is retained in addition to the public source tree. This is not a claim that an unmodified JDK checkout reproduces the vendor binary.

The official static SDK archive remains pinned to SHA256 `95520e5e01adebfb0c9fdce12e87c39d1e630e0d1fa1a7a5af2288efd1c89d00`. Its version has a corresponding [upstream `prep18-9` tag](https://github.com/johanvos/mobile/tree/prep18-9), pointing to `65db66f6d9c46c4bd0eaea87ac6ff3e035d43d49`; the commit's full source archive and original legal notices are retained. The unsigned tag is a version/source binding, not a cryptographic binary-build attestation.

## Linguistic data checks

- **French 0.7:** decoded all 666,726 tagger records from the actual pinned Maven JAR. The source dictionary, additions, removals and lemma correction from [release commit `ff11b57`](https://github.com/languagetool-org/french-pos-dict/tree/ff11b571918809d8ae39669a9c815c71c1d9fb6c) produce exactly the same distinct word/lemma/tag rows. The fixed `dict_tools` submodule commit is also archived.
- **Spanish 2.3:** the unmodified noun/adjective/verb generators and source data from [release commit `fbeef4f`](https://github.com/jaumeortola/spanish-dict-tools/tree/fbeef4f94e18c65daa51867a2aa1b724b423f54b) produce 3,689,171 records. After normalization, the generated and actual decoded tagger rows have the same complete sorted-byte SHA256 `866c51832d290851d81e8c9335eb74c3fbbc5815999e9276f20414dddd63ee02`.

Both dictionaries declare frequency data in the final tag byte. The comparison removes that byte in the same way as LanguageTool 6.6's actual `BaseTagger`. Frequency values and binary FSA serialization are explicitly outside this equivalence result. These checks establish dictionary-source correspondence for the tagger records; they do not establish general proofreading quality or close the app's 20-language acceptance.

All dictionary decoding/generation ran with network denied. Spanish generation could write only inside its new isolated source tree. Exact dictionary metadata and binary/source hashes are recorded in the two final source-proof JSON files. `probes/` preserves the actual small helpers used for the run; their relative working-directory assumptions are research reproduction inputs, not a completed end-user installation/relinking recipe.

## Materials and limits

The source mirror contains the existing 132 Maven source archives, six pinned upstream source tarballs, the actual bundled Java sources, original notices and the recorded provenance/probes. `SOURCE_PACKAGE.json` records its external-work-directory ZIP hash and size. Large archives, compiled probes and multi-million-row intermediate files stay outside Git. [Original notice inventory](../../docs/licenses/native-engine-source-bindings-20261015/README.md).

Thirteen focused Python regression tests pass. No app/runtime source changed in this checkpoint, so no new app build or native-engine execution result is inferred from these tooling tests. The earlier actual framework/worker execution evidence remains separate.

Remaining work includes preferred-source/resource-specific review for ten other linguistic-data artifacts, native runtime build correspondence, final relinking/installation materials and application terms, then production app availability/integration and broader language acceptance. R14 and the full application objective remain open.
