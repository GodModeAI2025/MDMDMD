#!/usr/bin/env python3
"""Compare every non-META-INF resource in a data-only JAR with a pinned tar.

This proves exact resource correspondence only. Missing same-path members are
reported as such, not as absence of preferred sources or a legal determination.
The tool never extracts archive paths or executes upstream code.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile
import zipfile

MAX_MEMBER = 100 * 1024 * 1024
MAX_TOTAL = 2 * 1024 * 1024 * 1024
MAX_ENTRIES = 200_000


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def validate_path(name, seen):
    path = PurePosixPath(name)
    if not name or path.is_absolute() or ".." in path.parts or "\\" in name or "\0" in name or name in seen:
        raise ValueError("Unsafe or duplicate archive path")
    seen.add(name)


def compare(jar_path, archive_path):
    resources = {}
    with zipfile.ZipFile(jar_path) as jar:
        seen, total = set(), 0
        entries = jar.infolist()
        if len(entries) > MAX_ENTRIES:
            raise ValueError("JAR entry bound exceeded")
        for entry in entries:
            validate_path(entry.filename, seen)
            total += entry.file_size
            if total > MAX_TOTAL or entry.file_size > MAX_MEMBER:
                raise ValueError("JAR data bound exceeded")
            if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError("JAR resource symlink")
            if entry.filename.endswith(".class"):
                raise ValueError("Expected a data-only artifact")
            if entry.is_dir() or entry.filename.startswith("META-INF/"):
                continue
            resources[entry.filename] = {"bytes": entry.file_size, "sha256": digest(jar.read(entry))}
    if not resources:
        raise ValueError("No data resources to compare")
    candidates = {name: [] for name in resources}
    with tarfile.open(archive_path) as archive:
        seen, total, count = set(), 0, 0
        for member in archive:
            validate_path(member.name, seen)
            total += member.size; count += 1
            if total > MAX_TOTAL or member.size > MAX_MEMBER or count > MAX_ENTRIES:
                raise ValueError("Source data bound exceeded")
            if member.isdev() or member.isfifo():
                raise ValueError("Source special file")
            if not member.isfile():
                continue  # No links are followed or extracted.
            for name in resources:
                if member.name == name or member.name.endswith("/" + name):
                    with archive.extractfile(member) as stream:
                        raw = stream.read(MAX_MEMBER + 1)
                    if len(raw) != member.size:
                        raise ValueError("Truncated source member")
                    candidates[name].append({"path": member.name, "bytes": member.size, "sha256": digest(raw)})
    matched, missing, different = [], [], []
    for name, expected in resources.items():
        values = candidates[name]
        exact = [value for value in values if value["sha256"] == expected["sha256"] and value["bytes"] == expected["bytes"]]
        if exact:
            matched.append({"resource": name, **expected, "upstream": exact})
        elif values:
            different.append({"resource": name, **expected, "upstream": values})
        else:
            missing.append({"resource": name, **expected})
    return {
        "binaryArtifact": jar_path.name, "binarySHA256": file_digest(jar_path),
        "sourceArchive": archive_path.name, "sourceArchiveSHA256": file_digest(archive_path),
        "resourceCount": len(resources), "matched": matched, "missingSamePath": missing,
        "differentSamePath": different, "allResourcesByteIdentical": len(matched) == len(resources),
        "scope": "Complete non-META-INF data-only JAR resources. Exact byte correspondence, not preferred-source, licensing or distribution approval."
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jar", required=True, type=Path)
    parser.add_argument("--source-archive", required=True, type=Path)
    parser.add_argument("--expected-jar-sha256", required=True)
    parser.add_argument("--expected-source-sha256", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if file_digest(args.jar) != args.expected_jar_sha256 or file_digest(args.source_archive) != args.expected_source_sha256:
        raise ValueError("Inputs differ from pinned receipts")
    if args.output.exists():
        raise ValueError("Existing evidence must not be overwritten")
    result = compare(args.jar, args.source_archive)
    with args.output.open("x", encoding="utf-8") as output:
        json.dump(result, output, ensure_ascii=False, indent=2); output.write("\n")
    print(json.dumps({k: result[k] for k in ["resourceCount", "allResourcesByteIdentical"]}))
    return 0 if result["allResourcesByteIdentical"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
