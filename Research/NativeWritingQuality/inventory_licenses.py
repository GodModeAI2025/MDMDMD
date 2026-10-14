#!/usr/bin/env python3
"""Retain declared license metadata and embedded notices without legal inference."""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile


def sha(value):
    return hashlib.sha256(value).hexdigest()


def declarations(pom, repository, visited=None):
    visited = set() if visited is None else visited
    if not pom.is_file() or pom in visited:
        return [], {"unresolvedPom": str(pom)}
    visited.add(pom)
    raw = pom.read_bytes()
    root = ET.fromstring(raw)
    prefix = root.tag.split("}")[0] + "}" if "}" in root.tag else ""
    def text(node, name):
        return node.findtext(prefix + name, default="").strip()
    values = root.find(prefix + "licenses")
    if values is not None and len(values):
        return [{"name": text(value, "name"), "url": text(value, "url"),
                 "distribution": text(value, "distribution"), "comments": text(value, "comments")}
                for value in values], {"pom": str(pom.relative_to(repository)), "sha256": sha(raw)}
    parent = root.find(prefix + "parent")
    if parent is None:
        return [], {"unresolvedPom": str(pom.relative_to(repository)), "reason": "No declared license or parent"}
    group, artifact, version = (text(parent, key) for key in ["groupId", "artifactId", "version"])
    if not all([group, artifact, version]) or any("${" in value for value in [group, artifact, version]):
        return [], {"unresolvedPom": str(pom.relative_to(repository)), "reason": "Unresolved parent coordinates"}
    parent_pom = repository.joinpath(*group.split("."), artifact, version, artifact + "-" + version + ".pom")
    return declarations(parent_pom, repository, visited)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--classpath", type=Path, required=True)
    parser.add_argument("--maven-repository", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--distribution-archive", type=Path)
    parser.add_argument("--runtime-home", type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    repository = args.maven_repository.resolve()
    notices = output / "notice-texts"
    notices.mkdir(exist_ok=True)
    records, missing = [], []
    for entry in args.classpath.read_text().strip().split(":"):
        jar = Path(entry).resolve()
        if jar.suffix != ".jar":
            continue
        # A classified JAR (for example -ipadic) shares its unclassified POM.
        pom = jar.parent / (jar.parent.parent.name + "-" + jar.parent.name + ".pom")
        licenses, provenance = declarations(pom, repository)
        embedded = []
        with zipfile.ZipFile(jar) as archive:
            for name in archive.namelist():
                if name.endswith("/") or not any(token in Path(name).name.upper() for token in ["LICENSE", "NOTICE", "COPYING"]):
                    continue
                raw = archive.read(name)
                fingerprint = sha(raw)
                # Keep exact bytes, including encodings and original line endings.
                target = notices / (fingerprint + ".txt")
                if target.exists() and target.read_bytes() != raw:
                    raise ValueError("Notice hash collision")
                target.write_bytes(raw)
                embedded.append({"entry": name, "bytes": len(raw), "sha256": fingerprint,
                                 "retainedFile": "notice-texts/" + target.name})
        if not licenses:
            missing.append(jar.name)
        records.append({"artifact": jar.name, "sha256": sha(jar.read_bytes()),
                        "licenses": licenses, "declarationSource": provenance, "embeddedNotices": embedded})
    supplemental = []
    def retain(raw, origin):
        fingerprint = sha(raw)
        target = notices / (fingerprint + ".txt")
        if target.exists() and target.read_bytes() != raw:
            raise ValueError("Notice hash collision")
        target.write_bytes(raw)
        supplemental.append({"origin": origin, "bytes": len(raw), "sha256": fingerprint,
                             "retainedFile": "notice-texts/" + target.name})
    distribution = None
    if args.distribution_archive:
        archive_path = args.distribution_archive.resolve()
        fingerprint = sha(archive_path.read_bytes())
        if fingerprint != "53600506b399bb5ffe1e4c8dec794fd378212f14aaf38ccef9b6f89314d11631":
            raise ValueError("LanguageTool 6.6 distribution pin mismatch")
        distribution = {"name": archive_path.name, "sha256": fingerprint,
                        "source": "https://languagetool.org/download/LanguageTool-6.6.zip"}
        with zipfile.ZipFile(archive_path) as archive:
            for name in archive.namelist():
                if not name.endswith("/") and (name == "LanguageTool-6.6/COPYING.txt" or name.startswith("LanguageTool-6.6/third-party-licenses/")):
                    retain(archive.read(name), "LanguageTool-6.6.zip:" + name)
    runtime_home = args.runtime_home.resolve() if args.runtime_home else None
    if runtime_home:
        for notice in sorted((runtime_home / "legal").rglob("*")):
            if notice.is_file():
                retain(notice.read_bytes(), "Gluon-GraalVM-Java17:legal/" + str(notice.relative_to(runtime_home / "legal")))
    report = {"artifacts": records, "unresolvedDeclarations": missing,
              "scope": "Pinned classpath upper-bound inventory, not native reachability or distribution approval",
              "interpretation": "Multiple license entries are retained without assuming alternatives or combined obligations",
              "distributionArchive": distribution, "supplementalNotices": supplemental,
              "runtimeNoticeScope": "Upper-bound JDK notices retained; target static-SDK/source obligations remain separate",
              "nativeRuntimeSDKCovered": False, "resourceSpecificLicensesFullyReviewed": False}
    (output / "INVENTORY.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"artifacts": len(records), "unresolvedDeclarations": missing,
                      "uniqueEmbeddedNotices": len(list(notices.iterdir()))}, indent=2))


if __name__ == "__main__":
    main()
