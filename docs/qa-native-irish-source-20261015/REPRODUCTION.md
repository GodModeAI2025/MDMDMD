# Reproducing the local Irish source proof

The full work tree remains at `work/native-irish-source-20261015` beneath the task root. All paths below are relative to the task root; choose a **fresh** output directory. Source URLs and exact hashes are in SOURCE_RECEIPTS.json; Gaelspell has its own receipts. No downloaded code is run by the FST verifier itself.

## Verify retained build and decoding outputs

```sh
python3 -B outputs/Skriptum/Research/NativeWritingQuality/verify_irish_fst_source.py \
  --fst-archive work/native-irish-source-20261015/upstream/irishfst-pr13-head.tar.gz \
  --release-archive work/native-quality-data-review-20261015/Irish-0.02.tar.gz \
  --jar work/native-quality-aot-20261014/m2/io/github/jimregan/languagetool-ga-dicts/0.02/languagetool-ga-dicts-0.02.jar \
  --tagger work/native-irish-source-20261015/decoded/tagger.tsv \
  --synthesis work/native-irish-source-20261015/decoded/synthesis.tsv \
  --source work/native-irish-source-20261015/irishfst-pr13-build \
  --perl work/native-irish-source-20261015/generated/tsv2tsv.pl \
  --builders work/native-irish-source-20261015/upstream \
  --pairs work/native-irish-source-20261015/generated/pairs.tsv \
  --perl-output work/native-irish-source-20261015/generated/tagger.tsv \
  --output work/native-irish-source-20261015/fresh-fst-verification
```

The final actual invocation used absolute versions of these paths from `/private/tmp`, exited 0, and is retained in VERIFICATION_COMMAND.json. The decoded-output SHA256 values are pinned, together with the unchanged input JAR and archive hashes. The full actual Java decoding commands and decoder/dependency hashes are in `decoded/COMMANDS.json` and `decoded/STATE.json`.

## Rebuild Foma and FST in a new owned directory

Retain the complete original archives and safe-extract each into a fresh directory using `archive_members`/`write_members` from verify_irish_gaelspell.py. No symlinks or traversal are permitted. Build only the local Foma executable with the recorded historical source; the local host already supplies clang, make, flex/bison, zlib, and Homebrew readline. The actual command was:

```sh
make -C foma-build/foma foma CC=clang SVN_REV=0 \
  'CFLAGS=-O2 -Wall -D_GNU_SOURCE -std=c99 -fcommon -DSVN_REV=0 -I/opt/homebrew/opt/readline/include' \
  'LDFLAGS=-L/opt/homebrew/opt/readline/lib -lreadline -lz -ltermcap'
```

No install target is needed. Prepend the new local Foma directory to PATH. In the fresh IrishFST tree, create `scratch/`, leave the original Makefile intact, and create Makefile.local with exactly these substitutions: `/tmp/` becomes `scratch/`; `@foma ` becomes `@foma -e "set quit-on-fail ON" `. Run `/usr/bin/make -j1 -f Makefile.local bin/all.fst`. The actual generated Makefile and hashes are retained, as are full Foma/FST build logs.

With the separate generated directory beside the FST source tree, run local Foma with `-f export.foma` (cwd FST tree). Its exact script is retained under generated/export.foma. Feed the resulting pairs.tsv through the unchanged release tsv2tsv.pl using `/usr/bin/perl`, preserving the complete output including the epsilon warning. The actual commands, exitcodes and output hashes are in generated/COMMANDS.json and generated/STATE.json.

## Gaelspell

Follow `gaelspell/REPORT.md` and the six recorded generator commands. The durable `verify_irish_gaelspell.py` snapshots and validates the exact source/JAR archives before running the original text generators in a new working copy; no global install or network access occurs. The source archive and Roman 1.24 remain outside Git.

## Tests

From the repository:

```sh
python3 -B -m unittest discover -s Research/NativeWritingQuality/tests -p 'test_irish*.py' -v
```

All 17 tests passed. No application licensing approval or fully packaged customer source offer follows from these reproduction commands.
