#!/usr/bin/env python3
"""Bind Irish 0.02 morphology to the unchanged IrishFST PR-13 source.

Offline research verifier; the separately recorded Foma/Perl/Java commands must
run first. Compares every form/lemma/tag, without normalizing Unicode or text.
Only the original generator's exact epsilon warning is ignored, as the original
LanguageTool builders document. No app distribution or legal approval follows.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

from compare_dictionary_archive import file_digest
from verify_irish_gaelspell import archive_members, digest
from verify_portuguese_source import checked_row, row_fingerprint, sort_rows

PINS = {
    "fst_archive": "66eab614b0dd785c5b20427c7f6990f7d6ee0f8e2ce631ab337234ad8b050e1c",
    "release_archive": "4c8a21caf6174d6dc753c9f31d17f63101112731c8d10bbe3b33420f09355d4a",
    "jar": "52a9ecb80eb72cbe1105ed68ce22d529eb6d5e830ff2d065cf99322bc5f795c0",
    "tagger": "d1aa38a2f129240f618d63cfa99aa1a944731337533be50ad215885f1cd8c162",
    "synthesis": "7a652cce4747451efd5e028f68998e47b533f9d5e49891ab99c3abbef972dccc",
}
BUILDERS = {
    "20180630-DictionaryBuilder.java": "c0edd7e10e0b1a1658c9cd6cd36cd05d5f488ee5164c2da0f3eb358e34ae420f",
    "20180630-POSDictionaryBuilder.java": "f8e4eb4cc3e6a8867dd8f37d494b015d8641cec1fa3aee2b29d06f25088af749",
    "20180630-SynthDictionaryBuilder.java": "dee44f111e60c506e5b114ec11f8fd2c2bdd98c65c1eebfdd2322c87cd042d4f",
}
TAGS = [f"SynthDictionaryBuilder{value}.txt_tags.txt" for value in (
    "5244965078244671751", "9149526588369088810", "122697023877489433",
    "124899850912439342", "1527682212194709169")]
RESOURCE_ROOT = "org/languagetool/resource/ga/"
ROW_PROOF = {"rows": 2081826,
             "sortedRowsSHA256": "7762db3b5639d680f75ea2bf40a5e6e10d1ead8f985f2166e513fc8678991bf2"}
LIMITATIONS = [
    "Complete tagger/synthesis row equivalence is proven, not byte-identical compiled FSA output.",
    "filter-archaic.txt's 45 entries are covered by the original generator's exclusions; the exact historical selection of this file is not reconstructed.",
    "This uses IrishFST PR 13 head d75491e468e4ed26acd236a81f837cfc77c83f4e, which is an unmerged upstream pull request, not the older README-linked fork head.",
    "Gaelspell spelling and its maintainer-backend preferred-source question are handled separately.",
    "Original GPL/LGPL/MIT/Apache notices remain separate. No application licensing, customer-ready source offer, installation or distribution approval is asserted.",
]


def bound_file(path, expected):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 1024**3:
        raise ValueError("Invalid or oversized input")
    actual = file_digest(path)
    if actual != expected:
        raise ValueError(f"Input hash mismatch: {path.name}")
    return {"bytes": path.stat().st_size, "sha256": actual}


def bind_original_tree(files, source):
    if source.is_symlink() or not source.is_dir():
        raise ValueError("Invalid original source directory")
    result = {}
    for name, (raw, _) in sorted(files.items()):
        local = source
        for part in Path(name).parts:
            local = local / part
            if local.is_symlink():
                raise ValueError("Original source symlink")
        result[name] = bound_file(local, digest(raw))
    return result


def convert_pair(line):
    """Exact tsv2tsv.pl conversion, restricted to valid pairs plus known epsilon."""
    if (len(line) > 4096 or not line.endswith(b"\n") or b"\r" in line
            or b"\x00" in line or line.count(b"\t") != 1):
        raise ValueError("Invalid FST pair")
    line.decode("utf-8", errors="strict")
    raw = line[:-1]
    if raw == b"++Num+Op\t+":
        return "plus", b""
    if raw == b"\t":
        return "epsilon", b"Error in line: \t\n"
    match = re.fullmatch(rb"([^+]*)([^\t]*)\t(.*)", raw)
    if not match:
        raise ValueError("Unrecognized FST pair")
    lemma, tags, surface = match.groups()
    tags = tags.replace(b"+", b"", 1).replace(b"+", b":")
    if not lemma or not tags or not surface:
        raise ValueError("Unexpected empty FST field; only the exact epsilon is allowed")
    row = checked_row(b"\t".join((surface, lemma, tags))) + b"\n"
    return ("filtered" if tags in (b"XMLTag", b"Event", b"Num:Op") else "row"), row


def convert_pairs(pairs, perl_output, rows):
    counts = {"pairs": 0, "row": 0, "epsilon": 0, "filtered": 0, "plus": 0}
    converted, raw_hash = hashlib.sha256(), hashlib.sha256()
    tags, excluded = set(), set()
    with pairs.open("rb") as source, rows.open("xb") as destination:
        for line in source:
            kind, value = convert_pair(line)
            counts["pairs"] += 1; counts[kind] += 1; raw_hash.update(line)
            if counts["pairs"] > 3_000_000 or source.tell() > 256 * 1024**2:
                raise ValueError("FST pair bounds exceeded")
            if kind == "filtered":
                excluded.add(value)
            elif kind in ("row", "epsilon"):
                converted.update(value)
                if kind == "row":
                    destination.write(value)
                    tag = value[:-1].split(b"\t")[2]
                    if not tag.isascii():
                        raise ValueError("Tag sorting requires original ASCII tag alphabet")
                    tags.add(tag)
    if converted.hexdigest() != file_digest(perl_output):
        raise ValueError("Original Perl output differs from exact pair conversion")
    return counts, tags, excluded, raw_hash.hexdigest(), converted.hexdigest()


def compare_inventories(archive, tags, excluded):
    raw = b"".join(tag + b"\n" for tag in sorted(tags))
    found = {name[len(RESOURCE_ROOT):] for name in archive.namelist()
             if name.startswith(RESOURCE_ROOT) and name.endswith("_tags.txt")}
    if found != set(TAGS):
        raise ValueError("Missing or unexpected release tag inventory")
    inventories = {}
    for name in TAGS:
        expected = archive.read(RESOURCE_ROOT + name)
        if expected != raw:
            raise ValueError(f"Tag inventory differs: {name}")
        inventories[name] = {"bytes": len(raw), "sha256": digest(raw), "byteIdentical": True}
    filter_raw = archive.read(RESOURCE_ROOT + "filter-archaic.txt")
    filter_rows = filter_raw.splitlines(keepends=True)
    if not filter_rows or any(not row.endswith(b"\n") for row in filter_rows):
        raise ValueError("Incomplete filter rows")
    for row in filter_rows:
        checked_row(row[:-1])
    covered = set(filter_rows) <= excluded
    if not covered:
        raise ValueError("Release filter contains entries absent from generator exclusions")
    return inventories, {"bytes": len(filter_raw), "sha256": digest(filter_raw),
        "rows": len(filter_rows), "allCoveredByOriginalGeneratorExclusions": covered,
        "additionalGeneratorExclusions": [row.decode("utf-8").rstrip("\n") for row in sorted(excluded - set(filter_rows))],
        "exactHistoricalSelectionReconstructed": False}


def verify(args):
    if args.output.exists() or args.output.is_symlink():
        raise ValueError("Use a fresh evidence directory")
    inputs = {key: bound_file(getattr(args, key), expected) for key, expected in PINS.items()}
    fst = archive_members(args.fst_archive)
    release = archive_members(args.release_archive)
    originals = bind_original_tree(fst, args.source)
    perl = release["scripts/tsv2tsv.pl"][0]
    inputs["perl"] = bound_file(args.perl, digest(perl))
    inputs["builders"] = {name: bound_file(args.builders / name, expected) for name, expected in BUILDERS.items()}
    args.output.mkdir(parents=True)
    temporary = args.output / "sort-temp"; temporary.mkdir()
    rows = args.output / "generated-rows.tsv"
    counts, tags, excluded, pairs_hash, perl_hash = convert_pairs(args.pairs, args.perl_output, rows)
    if counts != {"pairs": 2082363, "row": 2082306, "epsilon": 1, "filtered": 55, "plus": 1}:
        raise ValueError(f"Unexpected original generator counts: {counts}")
    results = {}
    for key, source in (("generated", rows), ("tagger", args.tagger), ("synthesis", args.synthesis)):
        sorted_rows = args.output / (key + "-sorted.tsv")
        sort_rows(source, sorted_rows, temporary)
        results[key] = row_fingerprint(sorted_rows)
    with zipfile.ZipFile(args.jar) as archive:
        inventories, filter_result = compare_inventories(archive, tags, excluded)
    success = all(result == ROW_PROOF for result in results.values()) and len(tags) == 3559
    here = Path(__file__).resolve().parent
    result = {"schema": 1, "sourceCommit": "d75491e468e4ed26acd236a81f837cfc77c83f4e",
        "builderSourceCommit": "b5de4fa9ca8687176ae52813294e103862da3c86",
        "inputs": inputs, "originalFSTFiles": originals,
        "pairExportSHA256": pairs_hash, "originalPerlOutputSHA256": perl_hash,
        "generatorCounts": counts, "duplicatesCollapsedByDictionary": counts["row"] - results["generated"]["rows"],
        "epsilonWarning": "Error in line: \\t\\n",
        "epsilonTreatment": "The unchanged Perl script emits one two-column warning for the epsilon pair. The release-era DictionaryBuilder.convertTabToSeparator and SynthDictionaryBuilder.reverseLineContent/collectTags explicitly ignore lines without exactly three tab-separated fields. No other malformed row is accepted.",
        "rows": results, "allRowsEqual": success, "distinctTags": len(tags),
        "tagInventories": inventories, "filter": filter_result, "limitations": LIMITATIONS,
        "toolSHA256": {name: file_digest(here / name) for name in (
            "verify_irish_fst_source.py", "verify_irish_gaelspell.py", "verify_portuguese_source.py", "compare_dictionary_archive.py")}}
    (args.output / "RESULT.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    if not success:
        raise ValueError("Complete source/release row correspondence failed; see RESULT.json")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in (*PINS, "source", "perl", "builders", "pairs", "perl_output", "output"):
        parser.add_argument("--" + name.replace("_", "-"), type=Path, required=True)
    args = parser.parse_args()
    result = verify(args)
    print(json.dumps({"allRowsEqual": result["allRowsEqual"], "rows": ROW_PROOF["rows"],
                      "distinctTags": result["distinctTags"], "remainingLimitations": result["limitations"]}, indent=2))


if __name__ == "__main__":
    main()
