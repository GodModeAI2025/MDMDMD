# Irish Gaelspell 4.8 source binding — 2026-10-15

The pinned LanguageTool Irish 0.02 JAR contains exact Gaelspell **v4.8** resources from commit `6f65d2a57197dd858d0101789ad98878bf410f3b` (2016-02-13). The original published source archive and original text-generation recipes reproduce `ga_IE.aff` (20,345 bytes) and `ga_IE.dic` (1,340,800 bytes, all 101,587 rows) byte for byte. Its 470-byte `LICENSES-en.txt` also matches. This is resource correspondence, not application licensing approval.

The source archive is `Gaelspell-v4.8-6f65d2a5.tar.gz`, SHA-256 `3034a3ee2a469545843fde0566e3184e3ec4a113fcb5f699c8fa108aeb163b75`. The locally loaded original dependency is `Roman-1.24.tar.gz`, SHA-256 `3080375bf5f96cb15310d1870a75472dc1fd2371273c6a546b81401b6f674a28`. `SOURCE_RECEIPTS.json` binds original URLs and exact bytes. `tags.json`, `releases.json` and `gaelspell-v48-commit.json` preserve the primary version evidence.

`SOURCE_BINDING.json` points to the full source-file inventory, final proof and command receipts. All six generator commands exited 0, with no stderr. Eight targeted tests passed: altered hashes and symlinks; archive traversal, aliases and file/parent collisions; malformed count/encoding; duplicate-row substitution; semantic-only equality without byte equality; existing output preservation; and explicit scope limits. Final verifier completed from the unrelated task-root working directory. Three fresh directories produced identical resource fingerprints.

## Reproduction

From this directory (choose a fresh output path):

```sh
python3 -B tools/verify_irish_gaelspell.py \
  --gaelspell Gaelspell-v4.8-6f65d2a5.tar.gz \
  --roman Roman-1.24.tar.gz \
  --jar ../../native-quality-aot-20261014/m2/io/github/jimregan/languagetool-ga-dicts/0.02/languagetool-ga-dicts-0.02.jar \
  --output fresh-verification
```

The JAR must have SHA-256 `52a9ecb80eb72cbe1105ed68ce22d529eb6d5e830ff2d065cf99322bc5f795c0`. The verifier has no network command and performs no global installation. It validates the pinned input snapshots before executing the original scripts in a new working copy. Original sources and notices remain intact under the output's `upstream-gaelspell` and `upstream-roman` directories. Notice copies are also bound in `NOTICE_MANIFEST.json`.

The adaptation is limited to deterministic `LC_ALL=C`, a local Perl `-I` path for Roman 1.24, and a portable ASCII count prepend instead of the upstream GNU `sed -i`/`wc` construct. The full upstream Makefile is preserved, but default targets, install targets and maintainer database regeneration are never run.

## Historical distinction

The LanguageTool PR's spelling dictionary import commit is dated 2017-03-22; its 0.02 merge is dated 2018-07-01. The matching Gaelspell source is the older release. An actual reconstruction of 2017-03-09 Gaelspell yielded 106,451 rows with 131 missing and 4,997 extra distinct rows relative to the target; May 2018 yielded 112,477 rows with 659 missing and 11,518 extra. `CANDIDATE_COMPARISONS.json` preserves these negative comparisons. The older matching archive must not be replaced silently by those newer snapshots.

## Remaining limits

- This proves only the two Hunspell text resources and their original notice. FST/tagger/synthesis/filter resources are separate work.
- The Gaelspell Makefile explains that `gaeilge.raw` is periodically generated from the maintainer's `Dictionary/IG` database using `Gin`. Those backend inputs/program are not reconstructed here. The proof begins with the original published v4.8 source files.
- Original Gaelspell README/affix/generator GPLv2-or-later notices, the separate `LICENSES-en.txt` wording, and Roman's original Perl terms are preserved without substitution. No application distribution or App Store rights conclusion is made.
- No app, simulator, portal, native engine build, production resource change, commit or push was performed.
