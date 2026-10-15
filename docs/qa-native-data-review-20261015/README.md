# Native grammar data review · 15 October 2026

Unshipped R14 preparation; no new engine app route or language-support claim.

## Additional Dutch, Asturian and English evidence

The `dutch/`, `asturian/` and `english/` subfolders retain pinned commit/download receipts, original notice/README/POM bytes, complete per-resource comparison results and fingerprints. The large validated archives remain outside Git. Dutch 0.1 at commit `ef481087db48df3369f0fc58f3ed2a11b0758a78` matches all nine actual JAR resources byte-for-byte; Asturian 0.1 at `c587ea3843dc581e98324f362e68cb7a3ef4b262` matches all eight. These are release-resource correspondence results. Their upstream READMEs explicitly describe binary-data repositories; no full preferred-source or distribution conclusion is inferred.

English 0.6 at `2c68994244eba9f54a0b561b9213c60c6cbf9c6c` has nine directly matching resource files and 20 resources without a same-path archive member. Those missing paths remain explicit. The source archive's generated tagger text nevertheless matches all **259,353** decoded actual word/lemma/tag rows. In addition, the two upstream Python files were read completely and the editable `src-clean.txt` rebuilt in a fresh directory with network and outside-directory writes denied. Its generated tagger rows again match all 259,353 actual dictionary entries, with no missing rows and no frequency stripping. Commands, complete input hashes and comparison receipts are in `english/`. No shell script was run. English synthesis/spelling binaries, native build correspondence, remaining language-data reviews and final source/relinking/application terms are not closed by this result.

The following German checkpoint and its original STATE file remain historical and unchanged.

The German POS dictionary has no 1.2.4 release tag. The public POM history identifies [commit 44c8cf0](https://github.com/languagetool-org/german-pos-dict/commit/44c8cf0bec57e4c6fb8b99f61afd094da5e1bc8f), whose POM declares version 1.2.4. The complete archive is retained outside Git at `work/native-quality-data-review-20261015/German-1.2.4-candidate.tar.gz`; its SHA256 is `4d90d0185eee3d2c23b378899409604bc3519bfebc29690ce1aa0b38391f667d`.

All five resources in the actual pinned Maven artifact match that upstream commit byte for byte: `german.dict`, `german_synth.dict`, both `.info` files and `german_tags.txt`. The proof records every complete file hash. Original upstream license and README bytes are retained here.

This is stronger upstream correspondence than a guessed tag or a current-branch download. It is not a new preferred-source/relinking or comprehensive quality result. The upstream README explicitly describes a repository of binary data and points to the [official dictionary export/build procedure](https://dev.languagetool.org/developing-a-tagger-dictionary). The source/data obligations are still reviewed per resource; the old count of ten remaining linguistic-data preferred-source reviews is not closed by this result.

The same official documentation links the actual Dutch repository [languagetool-org/dutch-pos-dict](https://github.com/languagetool-org/dutch-pos-dict). Its Maven POM's `dutch-dict-tools` URL returns 404. Follow the official link for the next Dutch source check rather than treating the stale POM URL as proof that no upstream material exists.

The archive validation rejects escaping paths, unsafe links and special files, verifies the commit API response and records archive size/hash. The five resource comparisons inspect complete actual JAR/tar members. No upstream script was executed and no private service or text was contacted. Large source archives and intermediate data stay outside Git. The previously retained French/Spanish semantic results and unresolved full native integration remain separate.
