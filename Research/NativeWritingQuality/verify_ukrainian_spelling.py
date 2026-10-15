#!/usr/bin/env python3
"""Full spelling-word comparison; retain binary frequencies without inventing source data."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from verify_ukrainian_generated import JAR_SHA256, compare_sorted, sha


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work-root", type=Path, required=True)
    parser.add_argument("--expanded", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    work, expanded, output = args.work_root.resolve(), args.expanded.resolve(), args.output.resolve()
    if output.exists():
        raise ValueError("Fresh output directory required")
    aot = work / "native-quality-aot-20261014"
    java = aot / "graalvm-svm-java17-darwin-m1-gluon-22.1.0.1-Final/Contents/Home/bin/java"
    libs = [aot / f"m2/org/carrot2/morfologik-{name}/2.1.9/morfologik-{name}-2.1.9.jar" for name in ("stemming", "fsa")]
    expected_libs = ["6170895b2315b697f4da5630caf57c6c441f1cb419d89d1cb5326b0673293e8a",
                     "1bfefce937df14cc94d32a98ce59c33f4d5b6c0eddbb436b6bfe27ff2120a23d"]
    jar = aot / "m2/ua/net/nlp/morfologik-ukrainian-lt/6.6.0/morfologik-ukrainian-lt-6.6.0.jar"
    source = expanded / "source/out/words_spell.txt"
    expansion = json.loads((expanded / "expand.json").read_text())
    if sha(jar) != JAR_SHA256 or sha(source) != expansion["sourceAfter"]["out/words_spell.txt"]:
        raise ValueError("Changed binary or expanded input")
    if any(sha(p) != expected for p, expected in zip(libs, expected_libs)):
        raise ValueError("Unpinned decoder dependency")
    here = Path(__file__).resolve().parent
    helper = here / "UkrainianSpellingRows.java"
    inputs = [Path(__file__), here / "verify_ukrainian_generated.py", helper, java, *libs, jar, source]
    before = {str(p): sha(p) for p in inputs}
    output.mkdir(parents=True)
    steps = []

    def run(name, command):
        print("Running " + name, flush=True)
        start = time.monotonic()
        with (output / (name + ".stdout")).open("xb") as stdout, (output / (name + ".stderr")).open("xb") as stderr:
            result = subprocess.run(command, stdout=stdout, stderr=stderr, cwd=output,
                                    env=dict(os.environ, LC_ALL="C"), timeout=120)
        steps.append({"name": name, "argv": list(map(str, command)), "exitCode": result.returncode,
                      "seconds": time.monotonic()-start, "timeoutSeconds": 120})
        (output / "steps.json").write_text(json.dumps(steps, indent=2) + "\n")
        if result.returncode:
            raise RuntimeError(name + " failed; inspect retained stderr")

    prefix = [java, "-Xmx128m", "-Dfile.encoding=UTF-8", "-cp", os.pathsep.join(map(str, libs)), helper]
    run("self-test", prefix + ["--self-test"])
    run("decode", prefix + [jar, output / "binary-words.txt", output / "binary-word-frequencies.tsv"])
    for kind, path in (("source", source), ("binary", output / "binary-words.txt")):
        run("sort-" + kind, ["/usr/bin/sort", "-u", "-S", "128M", "-T", output,
                             "-o", output / (kind + "-sorted.txt"), path])
    result = compare_sorted(output / "source-sorted.txt", output / "binary-sorted.txt")
    if before != {str(p): sha(p) for p in inputs}:
        raise ValueError("Verifier input changed")
    proof = {"scope": "Complete spelling word-set comparison; encoded frequency bins retained only as binary evidence, not reconstructed preferred-source frequencies",
             "wordSet": result, "SourceHashes": before, "allInputsUnchanged": True,
             "sourceFrequencyDataAvailable": False,
             "sourceFrequencyFilesMissing": ["distr/morfologik-ukrainian/src/main/data/uk_wordlist.xml", "all.tagged.freq.txt"],
             "frequencyBinarySHA256": sha(output / "binary-word-frequencies.tsv"),
             "sourceSortedSHA256": sha(output / "source-sorted.txt"),
             "binarySortedSHA256": sha(output / "binary-sorted.txt"), "steps": steps}
    (output / "SPELLING_WORD_COMPARISON.json").write_text(json.dumps(proof, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result, ensure_ascii=False, indent=2), flush=True)


if __name__ == "__main__":
    main()
