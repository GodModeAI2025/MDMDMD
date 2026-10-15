# Native grammar data review · 15 October 2026

Unshipped R14 preparation; no new engine app route or language-support claim.

The German POS dictionary has no 1.2.4 release tag. The public POM history identifies [commit 44c8cf0](https://github.com/languagetool-org/german-pos-dict/commit/44c8cf0bec57e4c6fb8b99f61afd094da5e1bc8f), whose POM declares version 1.2.4. The complete archive is retained outside Git at `work/native-quality-data-review-20261015/German-1.2.4-candidate.tar.gz`; its SHA256 is `4d90d0185eee3d2c23b378899409604bc3519bfebc29690ce1aa0b38391f667d`.

All five resources in the actual pinned Maven artifact match that upstream commit byte for byte: `german.dict`, `german_synth.dict`, both `.info` files and `german_tags.txt`. The proof records every complete file hash. Original upstream license and README bytes are retained here.

This is stronger upstream correspondence than a guessed tag or a current-branch download. It is not a new preferred-source/relinking or comprehensive quality result. The upstream README explicitly describes a repository of binary data and points to the [official dictionary export/build procedure](https://dev.languagetool.org/developing-a-tagger-dictionary). The source/data obligations are still reviewed per resource; the old count of ten remaining linguistic-data preferred-source reviews is not closed by this result.

The same official documentation links the actual Dutch repository [languagetool-org/dutch-pos-dict](https://github.com/languagetool-org/dutch-pos-dict). Its Maven POM's `dutch-dict-tools` URL returns 404. Follow the official link for the next Dutch source check rather than treating the stale POM URL as proof that no upstream material exists.

The archive validation rejects escaping paths, unsafe links and special files, verifies the commit API response and records archive size/hash. The five resource comparisons inspect complete actual JAR/tar members. No upstream script was executed and no private service or text was contacted. Large source archives and intermediate data stay outside Git. The previously retained French/Spanish semantic results and unresolved full native integration remain separate.
