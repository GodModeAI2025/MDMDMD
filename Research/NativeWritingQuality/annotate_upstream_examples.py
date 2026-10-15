#!/usr/bin/env python3
"""Extract maintainer correction attributes without changing a frozen selection."""
import argparse
import json
from pathlib import Path, PurePosixPath
from lxml import etree
from select_upstream_examples import literal, sha


def annotate(resources, corpus_raw):
    corpus = json.loads(corpus_raw)
    documents, records = {}, []
    for record in corpus["records"]:
        relative = PurePosixPath(record["xml"])
        if relative.is_absolute() or ".." in relative.parts or "\\" in str(relative):
            raise ValueError("Unsafe XML resource path")
        if str(relative) not in documents:
            raw = (resources / str(relative)).read_bytes()
            parser = etree.XMLParser(resolve_entities=False, load_dtd=False, no_network=True, recover=False)
            documents[str(relative)] = sha(raw), etree.fromstring(raw, parser)
        fingerprint, document = documents[str(relative)]
        if fingerprint != record["xmlSHA256"]:
            raise ValueError("XML does not match frozen selection")
        candidates = []
        incorrect = record["expect"] == "present"
        for example in document.findall(".//example"):
            if example.sourceline != record["sourceLine"]:
                continue
            value = literal(example, incorrect)
            if value is None or value["source"] != record["source"]:
                continue
            if incorrect and (value["offset"], value["length"]) != (record["offset"], record["length"]):
                continue
            candidates.append(example)
        if len(candidates) != 1:
            raise ValueError("Frozen example is not uniquely source-backed")
        correction = candidates[0].get("correction")
        records.append({"corrections": correction.split("|") if correction is not None else None})
    return {"selectionSHA256": sha(corpus_raw), "records": records}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resources", required=True, type=Path)
    parser.add_argument("--corpus", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = annotate(args.resources, args.corpus.read_bytes())
    with args.output.open("x", encoding="utf-8") as output:
        json.dump(result, output, ensure_ascii=False, indent=2); output.write("\n")


if __name__ == "__main__":
    main()
