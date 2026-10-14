#!/usr/bin/env python3
"""Reproducible offline C-ABI checks; deliberately separate from app acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--headers", type=Path, required=True)
    parser.add_argument("--library-directory", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    args = parser.parse_args()
    source = Path(__file__).resolve().parent
    repository = source.parents[1]
    output = args.artifacts.resolve()
    output.mkdir(parents=True, exist_ok=True)
    library = args.library_directory.resolve() / "libscriptum_native_quality.dylib"
    headers = args.headers.resolve()
    commands = []
    for name in ["NativeCorpusRunner", "NativeBoundaryProbe"]:
        command = ["xcrun", "swiftc", "-I", str(headers), "-import-objc-header",
                   str(headers / "com.mobilebox.research.nativewritingquality.h"),
                   str(source / (name + ".swift")), "-L", str(library.parent),
                   "-lscriptum_native_quality", "-Xlinker", "-rpath", "-Xlinker",
                   str(library.parent), "-o", str(output / name)]
        commands.append(command)
        with (output / (name + "-build.log")).open("wb") as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
    fixture = json.loads((source / "Fixtures/GrammarStyleParity.json").read_text())
    original = repository / fixture["sourceFixture"]
    if sha(original) != fixture["sourceSHA256"]:
        raise RuntimeError("Original full-engine fixture changed; do not silently regenerate parity expectations")
    cases = []
    for name, filename, expected in [("parity", "GrammarStyleParity", 29),
                                      ("correction-controls", "CorrectionControls", 29),
                                      ("long-chunks", "LongTextChunks", 5)]:
        cases.append((name, [str(output / "NativeCorpusRunner"),
                      str(source / ("Fixtures/" + filename + ".json")),
                      "--isolate-per-record", "--heap-mb=256"], expected))
    cases += [("boundaries", [str(output / "NativeBoundaryProbe")], None),
              ("heap-exhaustion", [str(output / "NativeBoundaryProbe"), "--heap-exhaustion"], None)]
    receipts = []
    for name, executable, expected in cases:
        command = ["/usr/bin/time", "-l", "/usr/bin/sandbox-exec", "-p",
                   "(version 1) (allow default) (deny network*)", *executable]
        commands.append(command)
        stdout, stderr = output / (name + ".json"), output / (name + ".stderr")
        with stdout.open("wb") as result_file, stderr.open("wb") as error_file:
            result = subprocess.run(command, stdout=result_file, stderr=error_file)
        parsed = None
        try:
            parsed = json.loads(stdout.read_text())
        except (ValueError, UnicodeError):
            pass
        valid = (isinstance(parsed, list) and len(parsed) == expected) if expected else (
            isinstance(parsed, dict) and parsed.get("passed") is True)
        metrics = stderr.read_text(errors="replace")
        peak = re.search(r"(\d+)\s+peak memory footprint", metrics)
        seconds = re.search(r"([\d.]+) real", metrics)
        receipt = {"name": name, "passed": result.returncode == 0 and valid,
                   "exitCode": result.returncode, "expectedRecords": expected,
                   "peakMemoryFootprintBytes": int(peak[1]) if peak else None,
                   "elapsedSeconds": float(seconds[1]) if seconds else None,
                   "outputSHA256": sha(stdout), "stderrSHA256": sha(stderr)}
        receipts.append(receipt)
        print(json.dumps(receipt), flush=True)
    report = {"passed": all(case["passed"] for case in receipts), "cases": receipts,
              "nativeLibrarySHA256": sha(library), "nativeLibraryBytes": library.stat().st_size,
              "originalFixtureSHA256": sha(original), "network": "denied by sandbox-exec",
              "appIntegrated": False, "iosExecutionProven": False,
              "scope": "Synthetic native C ABI verification, not comprehensive 20-language quality acceptance"}
    (output / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")
    (output / "STATE.json").write_text(json.dumps(report, indent=2) + "\n")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
