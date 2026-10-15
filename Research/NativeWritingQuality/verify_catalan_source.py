#!/usr/bin/env python3
"""Reproduce the bounded Catalan 2.26 tagger-source comparison.

Consumes complete TSV dumps made by the retained DumpDictionary.java against
the pinned actual JAR. Original build scripts are read as assembly evidence,
never executed. Frequency values, synthesis and spelling remain outside scope.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import tarfile
import zipfile
from compare_dictionary_archive import file_digest

INPUTS = ["resultats/lt/diccionari.txt", "resultats/lt/diccionari-dnv.txt",
          "build-morfologik-lt.sh", "morfologik-lt/sptotabs.pl"]


def transform(raw):
    rows = set()
    for line in raw.decode("utf-8").splitlines():
        if not line.strip() or re.search(r" (aguar|ciar|emblar|binar) ", line):
            continue
        tokens = line.split()
        if len(tokens) < 3 or len(tokens) % 2 != 1:
            raise ValueError("Unexpected source row")
        for index in range(1, len(tokens), 2):
            rows.add("\t".join([tokens[0], tokens[index], tokens[index + 1]]))
    return rows


def verify(archive_path, jar_path, decoded):
    inputs = {}
    with tarfile.open(archive_path) as archive:
        members = archive.getmembers()
        for relative in INPUTS:
            matches = [m for m in members if m.isfile() and m.name.endswith("/" + relative)]
            if len(matches) != 1 or matches[0].size > 100 * 1024**2:
                raise ValueError("Unbound or oversized source input")
            inputs[relative] = archive.extractfile(matches[0]).read()
    base = transform(inputs[INPUTS[0]]); extra = transform(inputs[INPUTS[1]])
    proofs = []
    with zipfile.ZipFile(jar_path) as jar:
        for name, expected in [("ca-ES", base), ("ca-ES-valencia", base | extra)]:
            metadata = jar.read("org/languagetool/resource/ca/" + name + ".info")
            if b"fsa.dict.frequency-included=true" not in metadata:
                raise ValueError("Frequency metadata does not match comparison policy")
            path = decoded / (name + "-2.26-decoded.tsv")
            actual = set()
            with path.open(encoding="utf-8") as stream:
                for line in stream:
                    word, stem, tag = line.rstrip("\n").split("\t")
                    actual.add("\t".join([word, stem, tag[:-1] if len(tag) > 1 else tag]))
            proofs.append({
                "variant": name, "sourceRows": len(expected), "binaryRows": len(actual),
                "sourceMissingFromBinary": len(expected - actual),
                "binaryMissingFromSource": len(actual - expected), "rowsEqual": actual == expected,
                "decodedSHA256": file_digest(path),
                "metadataSHA256": hashlib.sha256(metadata).hexdigest()
            })
    return {
        "sourceArchiveSHA256": file_digest(archive_path), "binaryArtifactSHA256": file_digest(jar_path),
        "inputSHA256": {key: hashlib.sha256(value).hexdigest() for key, value in inputs.items()},
        "proofs": proofs,
        "scope": "Original generated text, documented verb exclusion, original space-to-tab expansion, Valencia union/deduplication and declared final-frequency-byte removal. Not an editable-root, frequency, synthesis or spelling rebuild."
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["archive", "jar", "decoded", "output"]:
        parser.add_argument("--" + name, required=True, type=Path)
    parser.add_argument("--expected-archive-sha256", required=True)
    parser.add_argument("--expected-jar-sha256", required=True)
    args = parser.parse_args()
    if file_digest(args.archive) != args.expected_archive_sha256 or file_digest(args.jar) != args.expected_jar_sha256:
        raise ValueError("Inputs differ from pinned receipts")
    if args.output.exists():
        raise ValueError("Existing evidence must not be overwritten")
    result = verify(args.archive, args.jar, args.decoded)
    with args.output.open("x", encoding="utf-8") as output:
        json.dump(result, output, ensure_ascii=False, indent=2); output.write("\n")
    print(json.dumps(result["proofs"], ensure_ascii=False))
    return 0 if all(value["rowsEqual"] for value in result["proofs"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
