#!/usr/bin/env python3
"""Assemble retained source mirrors, later PT evidence and an offline relink kit.

Local integrity work only. No download, compiler, app installation or publication.
Historical evidence is preserved byte-for-byte, including its original scope.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import tempfile
import zipfile

from bundle_verified_materials import MAX_FILES, MAX_TOTAL, build, digest_file
from relink_native_kit import relative_path, verify_kit


DATA = "docs/qa-native-data-release-20261015"
PT = "docs/qa-native-portuguese-source-20261015"
SYNTH = "docs/qa-native-synthesis-source-20261015"
RELINK = "docs/qa-native-relink-20261015"
TOOLS = "Research/NativeWritingQuality"
OPEN_ITEMS = [
    "Irish: preferred FST/Gaelspell source correspondence and resource-specific terms remain open; retain the distinct dictionary/build-script/other-source notices.",
    "Ukrainian: root dictionary CC BY-NC-SA 4.0, software GPL 3+ and derivative LGPL 2.1+ notices are distinct; source/binary mapping and redistribution rights remain unresolved. This internal candidate is not approved for app/customer redistribution.",
    "Portuguese: full tagger and synthesis row equivalence is retained; spelling and byte-identical FSA serialization remain unproven.",
    "Other language resources, including Catalan non-tagger data and Belarusian/Crimean Tatar version/source bindings, still need resource-specific completion.",
    "Host JDK modified-tree and native SDK correspondence, full preferred-source rebuild, app reconstruction/library substitution, developer signing/installation and application terms remain incomplete.",
    "No production activation, customer-ready distribution, legal approval or completion of R14 is implied. Historical command logs may contain local paths; only the current assembly and relink recipes are relocatable.",
]


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()


def regular(path):
    path = Path(path).absolute()
    if path.is_symlink() or any(p.is_symlink() for p in path.parents) or not path.is_file():
        raise ValueError("Expected a regular file without symlink ancestors")
    return path


def fingerprint(value):
    if not isinstance(value, str) or not re.fullmatch(r"[a-f0-9]{64}", value):
        raise ValueError("Invalid SHA256 fingerprint")
    return value


def safe_name(value):
    relative_path(value)
    if "\0" in value or any(ord(c) < 32 for c in value) or value == ".":
        raise ValueError("Unsafe material path")
    return value


def source_tool(repo, name):
    """Use the original checkout layout or this candidate's retained tools."""
    base = repo / TOOLS if (repo / TOOLS).is_dir() else repo / "tools"
    return regular(base / safe_name(name))


def verified_package(path, receipt):
    """Check a retained archive and every member before extracting anything."""
    path = regular(path)
    if receipt.get("integrityVerified") is not True or path.stat().st_size != receipt["bytes"] or digest_file(path) != fingerprint(receipt["sha256"]):
        raise ValueError("Source package differs from retained receipt")
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        if not 1 < len(infos) <= MAX_FILES or sum(i.file_size for i in infos) > MAX_TOTAL:
            raise ValueError("Source package exceeds bounds")
        seen = set()
        for info in infos:
            name = safe_name(info.filename)
            mode = info.external_attr >> 16
            if name.casefold() in seen or info.is_dir() or stat.S_IFMT(mode) not in (0, stat.S_IFREG):
                raise ValueError("Duplicate, aliased or non-regular archive member")
            seen.add(name.casefold())
        if archive.getinfo("MANIFEST.json").file_size > 16 * 1024 * 1024:
            raise ValueError("Source manifest exceeds bounds")
        raw = archive.read("MANIFEST.json")
        if hashlib.sha256(raw).hexdigest() != fingerprint(receipt["manifestSHA256"]):
            raise ValueError("Source manifest differs from receipt")
        manifest = json.loads(raw)
        records = manifest["files"]
        names = [safe_name(item["path"]) for item in records]
        if manifest.get("schema") != 1 or len(names) != len(set(n.casefold() for n in names)) or "manifest.json" in {n.casefold() for n in names}:
            raise ValueError("Invalid source manifest")
        if {i.filename for i in infos} != set(names) | {"MANIFEST.json"} or len(infos) != receipt["entries"]:
            raise ValueError("Unlisted or missing source package member")
        if not set(manifest["requiredPaths"]).issubset(names):
            raise ValueError("Missing required source notice/material")
        if manifest["unresolved"] != receipt["unresolved"]:
            raise ValueError("Historical limitations differ from receipt")
        total = 0
        for item in records:
            info = archive.getinfo(item["path"])
            if type(item["bytes"]) is not int or item["bytes"] < 0 or info.file_size != item["bytes"]:
                raise ValueError("Invalid source member size")
            digest = hashlib.sha256()
            with archive.open(info) as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
            if digest.hexdigest() != fingerprint(item["sha256"]):
                raise ValueError("Source member differs from manifest")
            total += item["bytes"]
        if total != receipt["materialBytes"]:
            raise ValueError("Source byte count differs from receipt")
        return manifest


def evidence_files(root):
    """Require the complete retained evidence directory and its checksum ledger."""
    root = Path(root).absolute()
    sums = regular(root / "SHA256SUMS")
    records = {}
    for line in sums.read_text().splitlines():
        expected, name = line.split("  ", 1)
        safe_name(name); fingerprint(expected)
        if name.casefold() in {n.casefold() for n in records} or name == "SHA256SUMS":
            raise ValueError("Duplicate evidence entry")
        file = regular(root / name)
        if digest_file(file) != expected:
            raise ValueError("Retained evidence changed: " + name)
        records[name] = expected
    actual = set()
    for directory, directories, files in os.walk(root, followlinks=False):
        if any((Path(directory) / name).is_symlink() for name in directories + files):
            raise ValueError("Symlink in evidence directory")
        actual.update((Path(directory) / name).relative_to(root).as_posix() for name in files)
    if not records or actual != set(records) | {"SHA256SUMS"}:
        raise ValueError("Unlisted or missing evidence file")
    records["SHA256SUMS"] = digest_file(sums)
    return records


def portuguese_chain(tagger_path, synthesis_path, source_archive_sha):
    tagger = json.loads(regular(tagger_path).read_text())
    synth = json.loads(regular(synthesis_path).read_text())
    rows = tagger["generated"]
    if type(rows.get("rows")) is not int or rows["rows"] <= 0:
        raise ValueError("Missing complete Portuguese row count")
    fingerprint(rows["sortedRowsSHA256"])
    if (tagger.get("rowsEqual") is not True or tagger["release"] != rows
            or synth.get("allRowsEqual") is not True or synth["source"] != rows or synth["synthesis"] != rows
            or synth["sourceProofSHA256"] != digest_file(tagger_path)
            or tagger["sourceArchiveSHA256"] != source_archive_sha
            or synth.get("tagInventoryEqual") is not True
            or type(synth.get("synthesisTags")) is not int or synth["synthesisTags"] <= 0
            or synth["synthesisTags"] != synth["inventoryTags"]):
        raise ValueError("Portuguese tagger/synthesis evidence is not one complete source chain")
    return {"rows": rows["rows"], "sortedRowsSHA256": rows["sortedRowsSHA256"],
            "tags": synth["synthesisTags"], "sourceArchiveSHA256": source_archive_sha,
            "taggerProofSHA256": digest_file(tagger_path), "synthesisProofSHA256": digest_file(synthesis_path),
            "spellingProven": False, "byteIdenticalFSAProven": False}


def assemble(repo, v3, portuguese, kit, output):
    repo, kit = Path(repo).resolve(strict=True), Path(kit).absolute()
    output = Path(output).absolute()
    if output.exists() or output.is_symlink():
        raise ValueError("Use a fresh assembly output directory")
    receipts = {"v3": json.loads(regular(repo / DATA / "SOURCE_PACKAGE.json").read_text()),
                "portuguese": json.loads(regular(repo / PT / "SOURCE_PACKAGE.json").read_text())}
    manifests = {"v3": verified_package(v3, receipts["v3"]),
                 "portuguese": verified_package(portuguese, receipts["portuguese"])}
    evidence = {name: evidence_files(repo / name) for name in (PT, SYNTH, RELINK)}
    for ledger in (json.loads((repo / PT / "TOOL_HASHES.json").read_text()),
                   json.loads((repo / RELINK / "STATE.json").read_text())["sourceSHA256"]):
        for name, expected in ledger.items():
            safe_name(name)
            file = source_tool(repo, name[len(TOOLS) + 1:]) if name.startswith(TOOLS + "/") else regular(repo / name)
            if digest_file(file) != fingerprint(expected):
                raise ValueError("Tool differs from retained proof: " + name)
    kit_manifest = verify_kit(kit)
    if digest_file(kit / "MANIFEST.json") != digest_file(repo / RELINK / "KIT_MANIFEST.json"):
        raise ValueError("Relink kit differs from retained evidence")
    for original, packaged in (("NativeRelinkKit.md", "README.md"), ("relink_native_kit.py", "relink_native_kit.py")):
        if digest_file(source_tool(repo, original)) != digest_file(regular(kit / packaged)):
            raise ValueError("Current relink recipe differs from verified kit")
    pt_records = {item["path"]: item for item in manifests["portuguese"]["files"]}
    for required in ("upstream/Portuguese-1.2.0.tar.gz", "evidence/upstream/COPYING.txt", "evidence/upstream/README.md", "evidence/upstream/tagger-data-README.md"):
        if required not in pt_records:
            raise ValueError("Portuguese original source/notice is missing")
    if pt_records.get("evidence/ROW_EQUIVALENCE.json", {}).get("sha256") != digest_file(repo / PT / "ROW_EQUIVALENCE.json"):
        raise ValueError("Portuguese mirror does not bind the later synthesis source proof")
    chain = portuguese_chain(repo / PT / "ROW_EQUIVALENCE.json", repo / SYNTH / "ROW_EQUIVALENCE.json", pt_records["upstream/Portuguese-1.2.0.tar.gz"]["sha256"])
    # Keep earlier scope text verbatim as history, not as today's status.
    status = {"schema": 1, "kind": "scriptum-native-source-assembly-candidate",
              "scope": "Internal source/evidence and binary-relink input assembly; not customer-ready distribution.",
              "sources": receipts, "portuguese": chain,
              "relinkKitManifestSHA256": digest_file(kit / "MANIFEST.json"),
              "historicalUnresolved": {key: value["unresolved"] for key, value in manifests.items()},
              "unresolved": OPEN_ITEMS, "distributionApproved": False, "productionEnabled": False,
              "completeCorrespondingSource": False, "applicationInstallationProven": False}
    with tempfile.TemporaryDirectory(prefix="native-source-assembly-") as temporary:
        staging = Path(temporary).resolve()
        files = []
        def add(source, name, expected=None):
            source = regular(source)
            files.append({"source": str(source), "path": name, "sha256": expected or digest_file(source)})
        add(v3, "previous/SourceMaterialsV3.zip", receipts["v3"]["sha256"])
        add(portuguese, "portuguese/SourceMaterials.zip", receipts["portuguese"]["sha256"])
        # Accessible original notices and generators, plus the intact PT package.
        with zipfile.ZipFile(portuguese) as archive:
            for item in manifests["portuguese"]["files"]:
                destination = staging / "portuguese/materials" / item["path"]
                destination.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(item["path"]) as incoming, destination.open("xb") as outgoing:
                    shutil.copyfileobj(incoming, outgoing, 1024 * 1024)
                add(destination, "portuguese/materials/" + item["path"], item["sha256"])
        add(repo / DATA / "SOURCE_PACKAGE.json", DATA + "/SOURCE_PACKAGE.json")
        for directory, records in evidence.items():
            for name, expected in records.items():
                add(repo / directory / name, directory + "/" + name, expected)
        for item in kit_manifest["files"]:
            add(kit / item["path"], "relink/" + item["path"], item["sha256"])
        add(kit / "MANIFEST.json", "relink/MANIFEST.json", status["relinkKitManifestSHA256"])
        tool_names = ["assemble_native_source_candidate.py", "bundle_verified_materials.py", "relink_native_kit.py",
                      "prepare_native_relink_kit.py", "NativeRelinkKit.md", "tests/test_relink_kit.py",
                      "verify_portuguese_source.py", "test_portuguese_source.py", "DumpDictionary.java",
                      "SynthDictionaryRows.java", "SynthDictionaryRowsTest.java", "verify_synthesis_rows.py", "test_synthesis_rows.py"]
        for name in tool_names:
            add(source_tool(repo, name), "tools/" + name)
        add(source_tool(repo, "tests/test_source_assembly.py"), "tools/tests/test_source_assembly.py")
        for name, raw in (("ASSEMBLY.json", json_bytes(status)), ("README.md", README.encode())):
            path = staging / name; path.write_bytes(raw); add(path, name)
        spec = {"files": files, "requiredPaths": [item["path"] for item in files], "unresolved": OPEN_ITEMS}
        result = build(spec, [repo, Path(v3).resolve().parent, Path(portuguese).resolve().parent, kit.resolve(), staging], output)
    (output / "ASSEMBLY.json").write_bytes(json_bytes(status))
    return result


README = """# Internal native grammar source and relink candidate

This is a local engineering assembly, not a customer-ready source distribution,
legal approval or production package. Read ASSEMBLY.json and its unresolved list.

previous/SourceMaterialsV3.zip preserves the complete prior V3 mirror, including
its nested V2 mirror, original language archives and historical reviews.
portuguese/SourceMaterials.zip preserves the later PT mirror byte-for-byte.
portuguese/materials/ exposes its original source archive, build dependencies,
original notices and reconstruction tools. The later full tagger and synthesis
proofs are under docs/qa-native-portuguese-source-20261015 and
docs/qa-native-synthesis-source-20261015; current verifier sources are in tools/.
Historical logs and recipes retain their original paths and claims unchanged.
ASSEMBLY.json explains which later proofs supersede earlier open status text.

relink/ is the complete, hash-bound offline input kit, including binary objects,
runtime archives, resources, generated fallback source and current instructions.
It is not a preferred-source rebuild of the engine. After extracting this outer
archive into a fresh directory, from that directory run:

```sh
python3 -B tools/assemble_native_source_candidate.py --verify-directory .
python3 -B relink/relink_native_kit.py --verify-only
python3 -B relink/relink_native_kit.py --output ../relinked-frameworks
```

To reproduce this complete assembly into a fresh sibling directory, using only
the extracted candidate and Python (no original checkout or compiler):

```sh
python3 -B tools/assemble_native_source_candidate.py --repo . \\
  --v3-package previous/SourceMaterialsV3.zip \\
  --portuguese-package portuguese/SourceMaterials.zip \\
  --relink-kit relink --output ../reassembled-candidate
```

The historical Research/NativeWritingQuality tool paths map to tools/ here;
their retained hashes and original contents remain unchanged. Matching inputs
produce the same ZIP hash, independent of extraction and output directory.

Only the relink command with --output invokes the local Apple toolchain. It needs Apple-silicon
macOS, Xcode 27/SDKs and Python 3.9+. These commands do not install or upload an
app. Keep outputs outside the immutable extracted candidate. See relink/README.md
for framework layouts and remaining application-installation requirements.

Irish FST/Gaelspell preferred sources/terms and Ukrainian root/derivative rights
and source correspondence remain explicitly open. The Ukrainian CC BY-NC-SA,
GPL and derivative LGPL notices are distinct, not interchangeable. Other data,
SDK/modified-JDK correspondence, complete source rebuild and app terms remain
open. Including these materials in an internal assembly grants no new rights.
"""


def verify_directory(root):
    root = Path(root).absolute()
    manifest = json.loads(regular(root / "MANIFEST.json").read_text())
    if manifest.get("schema") != 1 or not 0 < len(manifest["files"]) <= MAX_FILES or sum(item["bytes"] for item in manifest["files"]) > MAX_TOTAL:
        raise ValueError("Invalid candidate manifest or bounds")
    names = set()
    for item in manifest["files"]:
        name = safe_name(item["path"])
        if name.casefold() in names or name.casefold() == "manifest.json":
            raise ValueError("Duplicate/reserved candidate member")
        names.add(name.casefold())
        file = regular(root / name)
        if type(item["bytes"]) is not int or item["bytes"] < 0 or file.stat().st_size != item["bytes"] or digest_file(file) != fingerprint(item["sha256"]):
            raise ValueError("Candidate bytes changed: " + name)
    actual = set()
    for directory, directories, files in os.walk(root, followlinks=False):
        if any((Path(directory) / name).is_symlink() for name in directories + files):
            raise ValueError("Candidate contains a symlink")
        actual.update((Path(directory) / name).relative_to(root).as_posix() for name in files)
    if actual != {item["path"] for item in manifest["files"]} | {"MANIFEST.json"}:
        raise ValueError("Unlisted or missing candidate member")
    if not set(manifest["requiredPaths"]).issubset(actual):
        raise ValueError("Required candidate material is missing")
    status = json.loads((root / "ASSEMBLY.json").read_text())
    if (status.get("kind") != "scriptum-native-source-assembly-candidate"
            or any(status.get(key) is not False for key in ("distributionApproved", "productionEnabled", "completeCorrespondingSource", "applicationInstallationProven"))
            or status.get("unresolved") != OPEN_ITEMS or manifest["unresolved"] != OPEN_ITEMS):
        raise ValueError("Candidate scope was changed")
    verified_package(root / "previous/SourceMaterialsV3.zip", status["sources"]["v3"])
    verified_package(root / "portuguese/SourceMaterials.zip", status["sources"]["portuguese"])
    if digest_file(root / "relink/MANIFEST.json") != status["relinkKitManifestSHA256"]:
        raise ValueError("Relink manifest binding differs")
    kit = verify_kit(root / "relink")
    chain = portuguese_chain(root / PT / "ROW_EQUIVALENCE.json", root / SYNTH / "ROW_EQUIVALENCE.json", status["portuguese"]["sourceArchiveSHA256"])
    if chain != status["portuguese"]:
        raise ValueError("Portuguese evidence binding differs")
    return {"integrityVerified": True, "files": len(manifest["files"]), "relinkFiles": len(kit["files"]),
            "portugueseRows": chain["rows"], "distributionApproved": False, "productionEnabled": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-directory", type=Path)
    parser.add_argument("--repo", type=Path)
    parser.add_argument("--v3-package", type=Path)
    parser.add_argument("--portuguese-package", type=Path)
    parser.add_argument("--relink-kit", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.verify_directory:
        result = verify_directory(args.verify_directory)
    else:
        if any(value is None for value in (args.repo, args.v3_package, args.portuguese_package, args.relink_kit, args.output)):
            parser.error("assembly requires --repo, --v3-package, --portuguese-package, --relink-kit and --output")
        result = assemble(args.repo, args.v3_package, args.portuguese_package, args.relink_kit, args.output)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
