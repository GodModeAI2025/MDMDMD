#!/usr/bin/env python3
"""Reproduce the input-only probe selection; no binary responses are read."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile

PACKAGE = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument("--output", required=True, type=Path)
parser.add_argument("--work-root", required=True, type=Path)
args = parser.parse_args()
out = args.output
assert not out.exists(), "Output must be a new directory"
old = args.work_root.resolve() / "native-quality-data-review-20261015/Ukrainian-6.6.0-candidate.tar.gz"
assert hashlib.sha256(old.read_bytes()).hexdigest() == "31abd7ea4239a611a007f053f6a06bfed951d3ed2b4de0fa672c6481537e9abf"
commit_file = PACKAGE / "upstream/github/release-period-last-commit.json"
assert hashlib.sha256(commit_file.read_bytes()).hexdigest() == "8707a3d02e1f3f485fee173f896f794b4ed4be927962707dec86851e0b827a8d"
old_lemmas = set()
with tarfile.open(old) as archive:
    for member in archive.getmembers():
        if member.isfile() and "/data/dict/" in member.name and member.name.endswith(".lst"):
            for line in archive.extractfile(member).read().decode().splitlines():
                if line and not line.startswith(("#", " ")):
                    old_lemmas.add(line.split()[0])
queries = []
for changed in json.loads(commit_file.read_text())["files"]:
    if not changed["filename"].startswith("data/dict/"):
        continue
    for line in changed["patch"].splitlines():
        if line.startswith("+") and not line.startswith("+++"):
            added = line[1:]
            if not added or added.startswith(("#", " ")):
                continue
            word = added.split()[0]
            if word not in old_lemmas:
                queries.append({"word": word, "sourcePath": changed["filename"], "addedSourceLine": added})
assert 0 < len(queries) < 100
words = "\n".join(sorted({x["word"] for x in queries})) + "\n"
assert hashlib.sha256(words.encode()).hexdigest() == "5357f2db2a66ea4e4f6eedb116daf71bee6d5623936a9fd9687362b5a918e645"
out.mkdir()
(out / "new-commit-queries.txt").write_text(words)
(out / "new-commit-queries.json").write_text(json.dumps({
    "selection": "All added data/dict first-column lemmas in 8eb833b absent as first-column lemma in any data/dict/*.lst of 4787f7a; frozen before reading binary lookups",
    "scope": "Candidate discrimination only; a match is not full reconstruction or proof of all source inputs",
    "queries": queries,
}, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({"queries": len(words.splitlines()), "wordListSHA256": hashlib.sha256(words.encode()).hexdigest()}))
