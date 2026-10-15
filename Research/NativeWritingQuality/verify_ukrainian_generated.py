#!/usr/bin/env python3
"""Compare full decoded LT resources with independently expanded dict_uk data.

This verifies content correspondence, not exact historical generator identity.
Raw inputs/decoded records are retained; no observed response changes expectations.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import zipfile

JAR_SHA256 = "3ff49f9b989e3c50eb8d96f4385906b3562b638607aeeddaffd90939695b66a5"
EXCLUDE_SYNTH = re.compile(rb":(?:subst|vulg|obsc|vis)")


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_source_row(raw):
    if not raw.endswith(b"\n") or any(x in raw for x in (b"\r", b"\t", b"\0")):
        raise ValueError("Unexpected source row encoding/delimiters")
    raw.decode("utf-8", errors="strict")
    fields = raw[:-1].split(b" ")
    if len(fields) != 3 or any(not field for field in fields):
        raise ValueError("Source row must preserve exactly word, lemma, and tag")
    return b"\t".join(fields) + b"\n", fields[2]


def compare_sorted(left, right, sample_limit=12):
    """Streaming set comparison of pre-sorted unique bytes; retain both directions."""
    source_only = binary_only = common = 0
    source_sample, binary_sample = [], []
    with left.open("rb") as a, right.open("rb") as b:
        x, y = a.readline(), b.readline()
        while x or y:
            if x and y and x == y:
                common += 1
                x, y = a.readline(), b.readline()
            elif x and (not y or x < y):
                source_only += 1
                if len(source_sample) < sample_limit:
                    source_sample.append(x.decode("utf-8").rstrip("\n"))
                x = a.readline()
            else:
                binary_only += 1
                if len(binary_sample) < sample_limit:
                    binary_sample.append(y.decode("utf-8").rstrip("\n"))
                y = b.readline()
    return {"contentEqual": source_only == binary_only == 0, "commonRows": common,
            "sourceOnlyRows": source_only, "binaryOnlyRows": binary_only,
            "sourceOnlySample": source_sample, "binaryOnlySample": binary_sample}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work-root", type=Path, required=True)
    parser.add_argument("--expanded", type=Path, required=True,
                        help="Successful reconstruct_ukrainian_source output directory")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    work, expanded, output = args.work_root.resolve(), args.expanded.resolve(), args.output.resolve()
    if output.exists():
        raise ValueError("Fresh output directory required")
    source = expanded / "source/out/dict_corp_lt.txt"
    expansion = json.loads((expanded / "expand.json").read_text())
    if sha(source) != expansion["sourceAfter"]["out/dict_corp_lt.txt"]:
        raise ValueError("Expanded source changed")
    aot = work / "native-quality-aot-20261014"
    jar = aot / "m2/ua/net/nlp/morfologik-ukrainian-lt/6.6.0/morfologik-ukrainian-lt-6.6.0.jar"
    if sha(jar) != JAR_SHA256:
        raise ValueError("Unpinned binary")
    java = aot / "graalvm-svm-java17-darwin-m1-gluon-22.1.0.1-Final/Contents/Home/bin/java"
    libs = [aot / f"m2/org/carrot2/morfologik-{name}/2.1.9/morfologik-{name}-2.1.9.jar" for name in ("stemming", "fsa")]
    expected_libs = ["6170895b2315b697f4da5630caf57c6c441f1cb419d89d1cb5326b0673293e8a",
                     "1bfefce937df14cc94d32a98ce59c33f4d5b6c0eddbb436b6bfe27ff2120a23d"]
    if any(sha(p) != expected for p, expected in zip(libs, expected_libs)):
        raise ValueError("Unpinned dictionary decoder library")
    here = Path(__file__).resolve().parent
    input_files = [Path(__file__), here / "DumpDictionary.java", here / "SynthDictionaryRows.java", java, *libs, jar, source]
    input_hashes = {str(p): sha(p) for p in input_files}
    output.mkdir(parents=True)
    (output / "sort-tmp").mkdir()
    steps = []

    def run(name, command, timeout=180):
        print("Running " + name, flush=True)
        start = time.monotonic()
        with (output / (name + ".stdout")).open("xb") as stdout, (output / (name + ".stderr")).open("xb") as stderr:
            result = subprocess.run(command, cwd=output, env=dict(os.environ, LC_ALL="C"),
                                    stdout=stdout, stderr=stderr, timeout=timeout)
        steps.append({"name": name, "argv": list(map(str, command)), "seconds": time.monotonic()-start,
                      "exitCode": result.returncode, "timeoutSeconds": timeout})
        (output / "steps.json").write_text(json.dumps(steps, indent=2) + "\n")
        if result.returncode:
            raise RuntimeError(name + " failed; inspect retained stderr")

    expected_pos, expected_synth = output / "source-pos.tsv", output / "source-synth.tsv"
    tags, synth_tags = set(), set()
    source_count = synth_count = 0
    with source.open("rb") as src, expected_pos.open("xb") as pos, expected_synth.open("xb") as synth:
        for raw in src:
            row, tag = canonical_source_row(raw)
            source_count += 1
            if source_count > 25_000_000:
                raise ValueError("Source exceeds record bound")
            pos.write(row)
            tags.add(tag)
            if not EXCLUDE_SYNTH.search(row):
                synth.write(row)
                synth_count += 1
                synth_tags.add(tag)
    results = {}
    with zipfile.ZipFile(jar) as archive:
        for name, expected in (("ukrainian_tags.txt", tags), ("ukrainian_synth.dict_tags.txt", synth_tags)):
            data = archive.read("org/languagetool/resource/uk/" + name)
            actual_lines = data.splitlines()
            actual = set(actual_lines)
            (output / name).write_bytes(data)
            (output / (name + ".source-sorted")).write_bytes(b"\n".join(sorted(expected)) + b"\n")
            results[name] = {"contentSetEqual": expected == actual, "sourceUniqueTags": len(expected),
                             "binaryUniqueTags": len(actual), "binaryDuplicateLines": len(actual_lines)-len(actual),
                             "sourceOnly": [x.decode() for x in sorted(expected-actual)],
                             "binaryOnly": [x.decode() for x in sorted(actual-expected)],
                             "byteEqualUnderByteSort": data == b"\n".join(sorted(expected)) + b"\n"}
    for label, helper, resource, expected in [
        ("pos", "DumpDictionary.java", "ukrainian.dict", expected_pos),
        ("synth", "SynthDictionaryRows.java", "ukrainian_synth.dict", expected_synth),
    ]:
        decoded = output / ("binary-" + label + ".tsv")
        run("decode-" + label, [java, "-Xmx256m", "-Dfile.encoding=UTF-8", "-cp", os.pathsep.join(map(str, libs)),
                               here / helper, jar, "org/languagetool/resource/uk/" + resource, decoded])
        ordered = []
        for kind, path in (("source", expected), ("binary", decoded)):
            dest = output / (kind + "-" + label + ".sorted.tsv")
            run("sort-" + kind + "-" + label, ["/usr/bin/sort", "-u", "-S", "128M", "-T", output / "sort-tmp", "-o", dest, path])
            ordered.append(dest)
        results[resource] = compare_sorted(*ordered)
        results[resource]["sourceSHA256"] = sha(ordered[0])
        results[resource]["decodedBinarySHA256"] = sha(ordered[1])
    if input_hashes != {str(p): sha(p) for p in input_files}:
        raise ValueError("Verifier input changed during comparison")
    proof = {"scope": "Full decoded content comparison to independently expanded candidate source; not original build identity or legal clearance",
             "sourceCommit": expansion["sourceCommit"], "sourceVersion": expansion["sourceVersion"],
             "jarSHA256": JAR_SHA256, "expandedInputSHA256": sha(source), "sourceRows": source_count,
             "sourceSynthRowsBeforeDeduplication": synth_count, "results": results,
             "spellingBinaryComplete": False, "missingSpellingFrequencySource": "distr/morfologik-ukrainian/src/main/data/uk_wordlist.xml",
             "releaseGeneratorVersionKnown": False, "steps": steps,
             "SourceHashes": input_hashes, "allInputsUnchanged": True}
    (output / "GENERATED_RESOURCE_COMPARISON.json").write_text(json.dumps(proof, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"sourceRows": source_count, "results": results}, ensure_ascii=False, indent=2), flush=True)


if __name__ == "__main__":
    main()
