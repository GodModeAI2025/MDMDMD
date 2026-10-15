# Irish 0.02 original-source correspondence — 2026-10-15

The previously unbound Irish morphology and spelling resources now have concrete, reproducible source correspondence. This is a local research result. Production resources, app/project files and the release configuration were not changed.

## Complete morphology comparison

The release commit explicitly points to [IrishFST PR 13](https://github.com/uidhonne/irishfst/pull/13). Its actual head is `d75491e468e4ed26acd236a81f837cfc77c83f4e` in `jimregan/irishfst-1`; the PR remains unmerged. The older fork linked in the release README is not substituted for this source.

The complete unchanged source archive (SHA256 `66eab614b0dd785c5b20427c7f6990f7d6ee0f8e2ce631ab337234ad8b050e1c`) was compiled locally using historical Foma 0.9.18alpha from `bad2f0930d898efe00aa7488d09eb93014c475f4`. No global installation occurred. A separate Makefile.local redirects temporary files and enables fail-fast Foma; every original source file is hash-compared against the archive.

The actual FST exports 2,082,363 pairs. The unchanged release `tsv2tsv.pl` produces 2,082,306 valid rows, one exact epsilon warning, and excludes 55 XMLTag/Event/Num:Op pairs plus the special plus operator. Collapsing 480 duplicate rows yields **2,081,826 complete unique form/lemma/tag rows**. These match **both** fully decoded pinned `irish.dict` and `irish_synth.dict`, with sorted SHA256 `7762db3b5639d680f75ea2bf40a5e6e10d1ead8f985f2166e513fc8678991bf2`. No Unicode normalization, case folding, tag removal or sampling is used.

All **3,559 tags** reconstruct each of the five 97,398-byte generated tag inventory files exactly (SHA256 `d579472b8ba9c0f02518f7d8cd57dadb78f226567a682edc9b3c864847a2b7bd`). See `fst/RESULT.json`.

The initial strict comparison correctly rejected `Error in line: \t\n`. The original release-era LanguageTool builders at `b5de4fa9ca8687176ae52813294e103862da3c86` explicitly ignore input lines without exactly three tab-separated fields. The verifier accepts only that exact epsilon warning, checks the complete original Perl-output hash, and rejects any other malformed pair. This explains the conversion behavior; it is not byte-identical FSA recompilation proof.

`filter-archaic.txt` has 45 rows, all already excluded by the original Perl conversion. Ten additional excluded rows are listed in the result. Its exact historical subset selection is **not** reconstructed, so byte correspondence for this filter's preferred source remains open. Its exclusions do not alter any of the proven final dictionary rows.

## Spelling correspondence

Official [Gaelspell v4.8](https://github.com/kscanne/gaelspell/tree/6f65d2a57197dd858d0101789ad98878bf410f3b) reproduces `ga_IE.aff` (20,345 bytes), `ga_IE.dic` (1,340,800 bytes; all 101,587 rows), and `LICENSES-en.txt` (470 bytes) byte for byte. The complete source archive SHA256 is `3034a3ee2a469545843fde0566e3184e3ec4a113fcb5f699c8fa108aeb163b75`. Six original text-generation commands, using local Roman 1.24, each exit 0. Newer 2017/2018 source candidates were actually generated and do not match. See `gaelspell/SOURCE_BINDING.json`, commands, candidate comparisons and original notices.

The upstream Makefile says `gaeilge.raw` is generated periodically from the maintainer's `Dictionary/IG` database and `Gin`. That backend is not reconstructed here. Exact published-source correspondence therefore does not by itself close preferred-form completeness.

## Verification and bounds

17 focused tests pass (9 FST, 8 Gaelspell). They reject changed source files, symlinks/unsafe archives, malformed or unexpectedly empty rows, missing/changed tag inventories, unmatched filter entries, byte-different spelling outputs and overwritten evidence. The full FST verifier completed from `/private/tmp`; Gaelspell completed in three fresh directories. All local build/generator/verification handles are terminal. `STATE.json`, receipts and `SOURCE_HASHES.json` bind the evidence to the current tools.

Original Irish GPLv2, Gaelspell GPLv2-or-later notices, LanguageTool LGPL2.1-or-later generator notices, Foma Apache 2.0 and Roman's original Perl terms are retained separately. No legal approval or application distribution conclusion is made. Customer source delivery, relinking/reinstallation and Ukrainian source/rights questions remain outside this result. No device, simulator, app, portal, commit or push action was performed.

Large original archives, full trees, binaries and row outputs stay outside Git under `work/native-irish-source-20261015`. Only small proofs/logs/notices are copied here. Cleanup removed 587,459,650 bytes of generated copies only after full size/SHA256 equality checks; canonical final rows, every original archive and the earlier failed comparison remain retained (`CLEANUP.json`).
