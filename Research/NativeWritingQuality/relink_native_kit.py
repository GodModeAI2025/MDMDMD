#!/usr/bin/env python3
"""Verify and relink an offline native grammar kit without installing an app."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def relative_path(value):
    if not isinstance(value, str):
        raise ValueError("A kit path must be a string")
    path = PurePosixPath(value)
    if not value or path.is_absolute() or path.as_posix() != value or ".." in path.parts or "\\" in value:
        raise ValueError("Unsafe kit path: " + value)
    return path


def regular_file(root, relative):
    path = root
    for component in relative_path(relative).parts:
        path = path / component
        if path.is_symlink():
            raise ValueError("Symlink in kit: " + relative)
    if not path.is_file():
        raise ValueError("Missing kit file: " + relative)
    return path


def verify_kit(root):
    root = Path(root).resolve(strict=True)
    manifest_path = regular_file(root, "MANIFEST.json")
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("schema") != 1 or manifest.get("kind") != "scriptum-native-relink-kit":
        raise ValueError("Unknown relink kit")
    records = manifest.get("files")
    if not isinstance(records, list) or not records:
        raise ValueError("Empty relink kit")
    names = set()
    for record in records:
        name = relative_path(record["path"]).as_posix()
        if name.casefold() in names or name.casefold() == "manifest.json":
            raise ValueError("Duplicate or reserved kit file: " + name)
        names.add(name.casefold())
        file = regular_file(root, name)
        if type(record.get("bytes")) is not int or record["bytes"] < 0 or not re.fullmatch(r"[a-f0-9]{64}", record.get("sha256", "")):
            raise ValueError("Invalid fingerprint: " + name)
        if file.stat().st_size != record["bytes"] or sha(file) != record["sha256"]:
            raise ValueError("Kit bytes changed: " + name)
    actual = set()
    for directory, directories, files in os.walk(root, followlinks=False):
        for name in directories + files:
            path = Path(directory) / name
            if path.is_symlink():
                raise ValueError("Unexpected kit symlink")
        actual.update((Path(directory) / name).relative_to(root).as_posix() for name in files)
    if actual != {r["path"] for r in records} | {"MANIFEST.json"}:
        raise ValueError("Kit has unlisted or missing files")
    inputs = manifest.get("inputs", {})
    expected = {"mac-object", "ios-object", "ios-fallbacks", "graal-home", "ios-runtime", "headers", "resources", "manifest"}
    if set(inputs) != expected:
        raise ValueError("Unexpected relink inputs")
    for key, name in inputs.items():
        relative_path(name)
        path = root / name
        if key in {"graal-home", "ios-runtime", "headers", "resources"}:
            if not path.is_dir() or not any(r["path"].startswith(name + "/") for r in records):
                raise ValueError("Empty input directory: " + name)
        else:
            regular_file(root, name)
            if name not in actual - {"MANIFEST.json"}:
                raise ValueError("Unlisted input: " + name)
    for name in ("tools/build_frameworks.py", "tools/IOSRuntimeCompatibility.c", "tools/IOSRuntimeCompatibility-LICENSE.txt"):
        regular_file(root, name)
    return manifest


def build_command(root, output, manifest):
    root = Path(root).resolve(strict=True)
    output = Path(output).absolute()
    if output.exists() or output.is_symlink():
        raise ValueError("Use a fresh output directory")
    if output.resolve().is_relative_to(root):
        raise ValueError("Keep build output outside the immutable kit")
    command = [sys.executable, "-B", str(root / "tools/build_frameworks.py")]
    for key, value in manifest["inputs"].items():
        command += ["--" + key, str(root / relative_path(value))]
    return command + ["--output", str(output)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kit", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    manifest = verify_kit(args.kit)
    if args.verify_only:
        print(json.dumps({"integrityVerified": True, "files": len(manifest["files"]), "distributionApproved": False}))
        return
    if args.output is None:
        parser.error("--output is required unless --verify-only is selected")
    command = build_command(args.kit, args.output, manifest)
    # Do not inherit a conflicting SDKROOT from another platform's shell.
    environment = os.environ.copy()
    environment.pop("SDKROOT", None)
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    subprocess.run(command, env=environment, check=True)
    result = json.loads((args.output / "STATE.json").read_text())
    receipt = {"kitManifestSHA256": sha(args.kit / "MANIFEST.json"),
               "inputIntegrityVerified": True, "platformsLinked": sorted(result["artifacts"]),
               "frameworkStateSHA256": sha(args.output / "STATE.json"),
               "applicationInstalled": False, "engineRecompiledFromSource": False,
               "distributionApproved": False,
               "scope": "Offline framework relink from pinned objects and runtime archives; not an application installation or full source rebuild."}
    with (args.output / "RELINK.json").open("x") as stream:
        json.dump(receipt, stream, indent=2); stream.write("\n")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
