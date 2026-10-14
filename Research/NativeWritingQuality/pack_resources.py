#!/usr/bin/env python3
"""Preserve LT rule/morphology bytes in a deterministic external data package."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import zipfile

PREFIXES = ("org/languagetool/resource/", "org/languagetool/rules/")
# Two pinned JARs intentionally contribute different versions of this file.
# Keep both in the native classpath, preserving getResources() multiplicity.
RETAINED = {"org/languagetool/resource/ga/filter-archaic.txt"}


def digest(value):
    return hashlib.sha256(value).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--classpath", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    data, origins, jars, retained = {}, {}, [], {}
    for entry in args.classpath.read_text().strip().split(":"):
        jar = Path(entry)
        if jar.suffix != ".jar":
            continue
        used = False
        with zipfile.ZipFile(jar) as archive:
            for member in archive.infolist():
                name = member.filename
                if not name.startswith(PREFIXES) or member.is_dir():
                    continue
                path = PurePosixPath(name)
                if path.is_absolute() or ".." in path.parts or "\\" in name:
                    raise ValueError("Unsafe resource path: " + name)
                content = archive.read(member)
                if name in data and data[name] != content and name not in RETAINED:
                    raise ValueError("Conflicting classpath resources: " + name)
                if name in RETAINED:
                    retained.setdefault(name, []).append({"jar": jar.name, "bytes": len(content), "sha256": digest(content)})
                data[name] = content
                origins.setdefault(name, []).append(jar.name)
                used = True
        if used:
            jars.append({"name": jar.name, "sha256": digest(jar.read_bytes())})
    if not data:
        raise ValueError("No rule resources selected")
    for name in retained:
        del data[name]
    manifest = {"engine": "LanguageTool", "version": "6.6", "jars": jars,
                "classPathRetained": retained,
                "resources": [{"path": name, "bytes": len(content), "sha256": digest(content),
                               "originJars": origins[name]} for name, content in sorted(data.items())]}
    raw_manifest = (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode()
    package = output / "LanguageTool-6.6-resources.zip"
    with zipfile.ZipFile(package, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, content in [*sorted(data.items()), ("manifest.json", raw_manifest)]:
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, content, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    # A clean, separately retained extraction is used only by the native probes.
    extracted = output / "resources"
    if extracted.exists():
        raise ValueError("Use a fresh output directory; extraction already exists")
    extracted.mkdir()
    with zipfile.ZipFile(package) as archive:
        for name in [*sorted(data), "manifest.json"]:
            target = extracted.joinpath(*PurePosixPath(name).parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists():
                raise ValueError("Resource collision on this filesystem: " + name)
            content = archive.read(name)
            expected = raw_manifest if name == "manifest.json" else data[name]
            if content != expected:
                raise ValueError("Package round-trip mismatch: " + name)
            target.write_bytes(content)
    for name, expected in data.items():
        if extracted.joinpath(*PurePosixPath(name).parts).read_bytes() != expected:
            raise ValueError("Extracted resource mismatch: " + name)
    receipt = {"resourceCount": len(data), "classPathRetainedPaths": sorted(retained), "uncompressedBytes": sum(map(len, data.values())),
               "packageBytes": package.stat().st_size, "packageSHA256": digest(package.read_bytes()),
               "manifestSHA256": digest(raw_manifest), "byteExactRoundTrip": True,
               "scope": "All rule and morphology resources retained; no language or rule subset removed"}
    (output / "manifest.json").write_bytes(raw_manifest)
    (output / "PACKAGE.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
