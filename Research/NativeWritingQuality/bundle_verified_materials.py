#!/usr/bin/env python3
"""Build a deterministic, hash-verified local source-material mirror.

Only explicitly listed, pinned regular files under caller-approved roots are
read. No downloads, source execution, credential discovery or app publication.
Package integrity is separate from source completeness and distribution rights.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import stat
import zipfile

MAX_TOTAL = 2 * 1024**3
MAX_FILES = 10_000


def digest_file(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def build(spec, allowed_roots, output):
    if output.exists():
        raise ValueError("Use a fresh output directory")
    roots = [p.resolve(strict=True) for p in allowed_roots]
    if not roots or not all(p.is_dir() for p in roots):
        raise ValueError("Explicit allowed input roots are required")
    items = spec["files"]
    if not items or len(items) > MAX_FILES:
        raise ValueError("Invalid material file count")
    entries, seen, total = [], {"manifest.json"}, 0
    for item in items:
        name = item["path"]; relative = PurePosixPath(name)
        if not name or relative.is_absolute() or ".." in relative.parts or "\\" in name or "\0" in name or str(relative) != name or name.casefold() in seen:
            raise ValueError("Unsafe, reserved or aliased package path")
        seen.add(name.casefold())
        original = Path(item["source"])
        if original.is_symlink():
            raise ValueError("Material input symlink")
        path = original.resolve(strict=True)
        if not any(path.is_relative_to(root) for root in roots) or not stat.S_ISREG(path.stat().st_mode):
            raise ValueError("Material input outside approved roots or not regular")
        total += path.stat().st_size
        if total > MAX_TOTAL:
            raise ValueError("Material size bound exceeded")
        if digest_file(path) != item["sha256"]:
            raise ValueError("Material differs from pinned receipt")
        entries.append((name, path, item["sha256"], path.stat().st_size, item.get("sourceReference", "")))
    entries.sort(key=lambda item: item[0])
    required = spec.get("requiredPaths", [])
    names = {item[0] for item in entries}
    if len(required) > MAX_FILES or any(name not in names for name in required):
        raise ValueError("A declared required material is absent")
    manifest = {
        "schema": 1,
        "scope": "Source-material mirror integrity only; not a claim of complete corresponding source or approved distribution.",
        "unresolved": spec["unresolved"],
        "requiredPaths": required,
        "files": [{"path": name, "sha256": fingerprint, "bytes": size, "sourceReference": reference}
                  for name, _, fingerprint, size, reference in entries]
    }
    manifest_raw = (json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()
    output.mkdir(parents=True, exist_ok=False)
    partial = output / "SourceMaterials.zip.partial"
    with zipfile.ZipFile(partial, "x") as archive:
        for name, path, expected, size, _ in entries:
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0)); info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_STORED if name.endswith((".zip", ".gz", ".jar")) else zipfile.ZIP_DEFLATED
            actual, count = hashlib.sha256(), 0
            with archive.open(info, "w", force_zip64=True) as destination, path.open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    destination.write(chunk); actual.update(chunk); count += len(chunk)
            if actual.hexdigest() != expected or count != size:
                raise ValueError("Material changed during packaging")
        info = zipfile.ZipInfo("MANIFEST.json", (1980, 1, 1, 0, 0, 0)); info.create_system = 3
        info.external_attr = 0o100644 << 16; info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, manifest_raw)
    with zipfile.ZipFile(partial) as archive:
        if archive.read("MANIFEST.json") != manifest_raw:
            raise ValueError("Packaged manifest differs")
        for item in manifest["files"]:
            actual = hashlib.sha256()
            with archive.open(item["path"]) as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    actual.update(chunk)
            if actual.hexdigest() != item["sha256"]:
                raise ValueError("Readback material hash mismatch")
    result = output / "SourceMaterials.zip"; partial.rename(result)
    receipt = {
        "file": result.name, "bytes": result.stat().st_size, "sha256": digest_file(result),
        "entries": len(entries) + 1, "materialBytes": total, "integrityVerified": True,
        "manifestSHA256": hashlib.sha256(manifest_raw).hexdigest(),
        "scope": manifest["scope"], "unresolved": spec["unresolved"]
    }
    (output / "MANIFEST.json").write_bytes(manifest_raw)
    (output / "PACKAGE.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", required=True, type=Path)
    parser.add_argument("--allow-input-root", action="append", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(build(json.loads(args.spec.read_text()), args.allow_input_root, args.output), ensure_ascii=False))


if __name__ == "__main__":
    main()
