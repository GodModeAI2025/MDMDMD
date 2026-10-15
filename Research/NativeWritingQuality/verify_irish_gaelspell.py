#!/usr/bin/env python3
"""Reproduce the two pinned Irish Hunspell text resources from Gaelspell 4.8.

Local, offline research only. Executes the pinned original text generators in a
fresh working copy, preserving original source files and notices. This does not
prove the FST resources, preferred-source completeness, or distribution rights.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import zipfile


COMMIT = "6f65d2a57197dd858d0101789ad98878bf410f3b"
PINS = {
    "gaelspell": "3034a3ee2a469545843fde0566e3184e3ec4a113fcb5f699c8fa108aeb163b75",
    "roman": "3080375bf5f96cb15310d1870a75472dc1fd2371273c6a546b81401b6f674a28",
    "jar": "52a9ecb80eb72cbe1105ed68ce22d529eb6d5e830ff2d065cf99322bc5f795c0",
}
RESOURCES = {
    "ga_IE.aff": "56476ea0e06e07282227619b3d2963aa4ac25568c22e3682fa025531adb21fff",
    "ga_IE.dic": "714dd751c14e771abccd92f5a3d2871aa6ec9b5b9cb925be9f71116b486aadf8",
    "LICENSES-en.txt": "50c34cb7939cbc234556a4466c57d664e593e5b90283c4a197a4baff66dabd3b",
}
LIMITATIONS = [
    "Only ga_IE.aff, ga_IE.dic and LICENSES-en.txt in the pinned Irish 0.02 JAR are proven here.",
    "Irish FST/tagger/synthesis/filter resources are outside this proof.",
    "Gaelspell Makefile describes gaeilge.raw regeneration from a maintainer backend Dictionary/IG and Gin; this check starts from the original published v4.8 files and does not reconstruct that backend.",
    "Original GPLv2-or-later notices and LICENSES-en.txt are retained; no application licensing or distribution approval is asserted.",
    "Roman 1.24 is a local text-generation dependency under its original Perl terms, not a shipped application component established by this proof.",
]
MAX_EXPANDED = 32 * 1024 * 1024


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()


def pinned_bytes(path, expected):
    path = Path(path)
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Not a regular, non-symlink input: {path}")
    raw = path.read_bytes()
    if digest(raw) != expected:
        raise ValueError(f"Input hash mismatch: {path.name}")
    return raw


def pinned_file(path, expected):
    raw = pinned_bytes(path, expected)
    return {"file": Path(path).name, "bytes": len(raw), "sha256": expected}


def archive_members(path, raw=None):
    """Validate every member before extraction; retain the original source bytes."""
    files = {}; seen = set(); roots = set(); total = 0
    with tarfile.open(fileobj=io.BytesIO(Path(path).read_bytes() if raw is None else raw), mode="r:gz") as archive:
        for index, member in enumerate(archive):
            name = member.name.rstrip("/")
            relative = PurePosixPath(name)
            if (index >= 1000 or not name or relative.is_absolute() or
                    relative.as_posix() != name or ".." in relative.parts or
                    "\\" in name or "\x00" in name or name.casefold() in seen or
                    not (member.isfile() or member.isdir())):
                raise ValueError(f"Unsafe source archive member: {member.name}")
            seen.add(name.casefold()); roots.add(relative.parts[0])
            if len(roots) != 1:
                raise ValueError("Source archive must have one root")
            if member.isfile():
                total += member.size
                if member.size < 0 or total > MAX_EXPANDED or len(relative.parts) < 2:
                    raise ValueError("Source archive exceeds file or size bounds")
                raw = archive.extractfile(member).read()
                if len(raw) != member.size:
                    raise ValueError("Short source archive member")
                files[PurePosixPath(*relative.parts[1:]).as_posix()] = (raw, member.mode)
    if not files:
        raise ValueError("Empty source archive")
    # Reject file/parent aliases, even when a directory was not explicitly listed.
    file_names = {name.casefold() for name in files}
    for name in files:
        if any(parent.as_posix().casefold() in file_names for parent in PurePosixPath(name).parents if parent.as_posix() != "."):
            raise ValueError("Source archive file/parent collision")
    return files


def write_members(files, output):
    output.mkdir()
    for name, (raw, mode) in files.items():
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
        target.chmod(0o755 if mode & 0o111 else 0o644)
    return [{"path": name, "bytes": len(raw), "sha256": digest(raw)}
            for name, (raw, _) in sorted(files.items())]


def dictionary_summary(raw):
    # Hunspell line count and UTF-8 are checked, not merely the set of headwords.
    text = raw.decode("utf-8")
    lines = text.splitlines()
    if not lines or not lines[0].isascii() or not lines[0].isdigit() or int(lines[0]) != len(lines) - 1:
        raise ValueError("Dictionary count header does not match all rows")
    return {"rows": len(lines) - 1, "sortedRowsSHA256": digest("\n".join(sorted(lines[1:])).encode("utf-8"))}


def compare_resource(name, actual, expected):
    result = {"resource": name, "bytes": len(actual), "sha256": digest(actual),
              "expectedBytes": len(expected), "expectedSHA256": digest(expected),
              "byteIdentical": actual == expected}
    if name.endswith(".dic"):
        result["generated"] = dictionary_summary(actual)
        result["release"] = dictionary_summary(expected)
        result["allRowsEqual"] = result["generated"] == result["release"]
    return result


def verify(gaelspell, roman, jar, output):
    output = Path(output)
    if output.exists() or output.is_symlink():
        raise ValueError("Output must be fresh")
    paths = {"gaelspell": gaelspell, "roman": roman, "jar": jar}
    # Execute exactly the bytes whose hashes passed, without reopening sources
    # after validation and allowing a changed archive to replace them.
    snapshots = {key: pinned_bytes(path, PINS[key]) for key, path in paths.items()}
    inputs = {key: {"file": Path(paths[key]).name, "bytes": len(raw), "sha256": digest(raw)}
              for key, raw in snapshots.items()}
    sources = archive_members(gaelspell, snapshots["gaelspell"])
    modules = archive_members(roman, snapshots["roman"])
    required = ["COPYING", "README", "LICENSES-en.txt", "Makefile", "isort", "roman.pl",
                "myspell-header", "hunspell-header", "ispellaff2myspell", "gaeilge.aff",
                "gaeilge.raw", "giorr.in", "stair", "miotas", "aitiuil", "eachtar",
                "gall", "gno", "daoine", "logainm"]
    if any(name not in sources for name in required) or any(name not in modules for name in ["README", "lib/Roman.pm"]):
        raise ValueError("Required source or original notice missing")
    with zipfile.ZipFile(io.BytesIO(snapshots["jar"])) as archive:
        expected = {name: archive.read("org/languagetool/resource/ga/hunspell/" + name) for name in RESOURCES}
    if any(digest(expected[name]) != value for name, value in RESOURCES.items()):
        raise ValueError("Pinned JAR resource hash mismatch")
    output.mkdir(parents=True)
    source_manifest = write_members(sources, output / "upstream-gaelspell")
    module_manifest = write_members(modules, output / "upstream-roman")
    work = output / "working-gaelspell"
    shutil.copytree(output / "upstream-gaelspell", work)
    commands = []
    environment = dict(os.environ)
    for key in ["PERL5OPT", "PERL5LIB", "BASH_ENV", "ENV", "CDPATH"]:
        environment.pop(key, None)
    environment.update(LC_ALL="C", LANG="C", PATH="/usr/bin:/bin")

    def run(command, destination):
        result = subprocess.run(["/bin/bash", "-euo", "pipefail", "-c", command],
                                cwd=work, env=environment, capture_output=True, timeout=60)
        commands.append({"command": command, "cwd": "working-gaelspell", "exitCode": result.returncode,
                         "stderr": result.stderr.decode("utf-8", errors="replace"),
                         "stdoutBytes": len(result.stdout), "stdoutSHA256": digest(result.stdout)})
        (output / "COMMANDS.json").write_bytes(json_bytes(commands))
        if result.returncode:
            raise ValueError(f"Generator failed; see COMMANDS.json: {command}")
        (work / destination).write_bytes(result.stdout)
        return result.stdout

    # Recipes transcribed from the pinned upstream Makefile. No default make,
    # install, backend database generation, or external pathname target is run.
    run("cat giorr.in | sed 's/ .*//' | sort -f", "giorr")
    run("sed 's/^[^:]*://' stair | sort -u", "stair.txt")
    run("sed 's/^[^:]*://' miotas | sort -u", "miotas.txt")
    run("perl -I../upstream-roman/lib roman.pl", "romhanach")
    body = run("bash ./isort gaeilge.raw aitiuil eachtar gall giorr gno romhanach daoine logainm miotas.txt stair.txt", "ga_IE.body")
    # Equivalent to the Makefile's GNU sed -i count prepend. The BSD wc utility
    # pads its count with spaces; explicit ASCII avoids that platform artifact.
    (work / "ga_IE.dic").write_bytes(str(body.count(b"\n")).encode("ascii") + b"\n" + body)
    (work / "myspelltemp.txt").write_bytes(sources["myspell-header"][0] + sources["hunspell-header"][0])
    run(r'''./ispellaff2myspell --charset=latin1 gaeilge.aff --myheader myspelltemp.txt | sed 's/""/0/' | sed '40,$s/"//g' | perl -p -e 's/^PFX S( +)([a-z])( +)[a-z]h( +)[a-z](.*)/print "PFX S$1$2$3$2h$4$2$5\nPFX S$1\u$2$3\u$2h$4\u$2$5";/e' | sed 's/S Y 9$/S Y 18/' | sed 's/\([]A-Z]\)1$/\1/' ''', "ga_IE.aff")
    checks = [compare_resource(name, (work / name).read_bytes(), expected[name]) for name in RESOURCES]
    report = {"schema": 1, "sourceCommit": COMMIT, "sourceTag": "v4.8", "inputs": inputs,
              "sourceFiles": source_manifest, "romanFiles": module_manifest, "resources": checks,
              "allResourcesByteIdentical": all(check["byteIdentical"] for check in checks),
              "verifierSHA256": digest(Path(__file__).read_bytes()), "limitations": LIMITATIONS,
              "adaptations": ["LC_ALL=C for deterministic source text sorting.",
                              "Roman 1.24 loaded with a local Perl -I path; no global installation.",
                              "GNU sed -i line count prepend replaced by explicit ASCII count and newline."],
              "applicationInstalled": False, "distributionApproved": False,
              "fullCorrespondingSourceProven": False}
    (output / "ROW_EQUIVALENCE.json").write_bytes(json_bytes(report))
    if not report["allResourcesByteIdentical"]:
        raise ValueError("Generated resources differ from pinned JAR; see ROW_EQUIVALENCE.json")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["gaelspell", "roman", "jar", "output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    report = verify(args.gaelspell, args.roman, args.jar, args.output)
    print(json.dumps({"allResourcesByteIdentical": report["allResourcesByteIdentical"],
                      "resources": report["resources"], "distributionApproved": False}, ensure_ascii=False))


if __name__ == "__main__":
    main()
