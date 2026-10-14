#!/usr/bin/env python3
"""Retain version-bound Maven sources/POMs/notices, without claiming legal completeness."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import urllib.error
import urllib.request
import zipfile
from notice_files import is_notice

MAVEN = "https://repo.maven.apache.org/maven2/"
MAX_SOURCE_BYTES = 50_000_000


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, url):
        raise ValueError("Unexpected source redirect")


def download(url, maximum):
    if not url.startswith(MAVEN):
        raise ValueError("Only public Maven Central source URLs are allowed")
    request = urllib.request.Request(url, headers={"User-Agent": "Scriptum-Source-Materials/1"})
    with urllib.request.build_opener(NoRedirect()).open(request, timeout=30) as response:
        raw = response.read(maximum + 1)
    if len(raw) > maximum:
        raise ValueError("Source download exceeds its bound")
    return raw


def validate_source(raw):
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        members = archive.infolist()
        if len(members) > 100_000 or sum(m.file_size for m in members) > 1_000_000_000:
            raise ValueError("Source archive exceeds extraction bounds")
        seen = set()
        for member in members:
            name = member.filename
            path = PurePosixPath(name)
            if path.is_absolute() or ".." in path.parts or "\\" in name or "\0" in member.orig_filename or name in seen:
                raise ValueError("Unsafe or duplicate source archive path")
            seen.add(name)
            if (member.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError("Source archive symlink")
        bad = archive.testzip()
        if bad:
            raise ValueError("Invalid source archive CRC")


def coordinates(jar, repository):
    relative = jar.resolve().relative_to(repository.resolve())
    parts = relative.parts
    if len(parts) < 4 or not all(re.fullmatch(r"[A-Za-z0-9_.+\-]+", v) for v in parts):
        raise ValueError("Invalid pinned Maven artifact path")
    artifact, version = parts[-3:-1]
    return relative, artifact, version


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--classpath", type=Path, required=True)
    parser.add_argument("--maven-repository", type=Path, required=True)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repository = args.maven_repository.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    pinned = json.loads(args.inventory.read_text())
    expected = {(r["artifact"], r["sha256"]) for r in pinned["artifacts"]}
    jars = [Path(value).resolve() for value in args.classpath.read_text().strip().split(":") if value.endswith(".jar")]
    actual = {(p.name, digest(p.read_bytes())) for p in jars}
    if actual != expected or len(jars) != len(expected):
        raise ValueError("Classpath does not match the retained binary inventory")
    notices = {}
    for jar in jars:
        relative, artifact, version = coordinates(jar, repository)
        pom = jar.parent / (artifact + "-" + version + ".pom")
        target = output / "poms" / relative.parent / pom.name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(pom.read_bytes())
        with zipfile.ZipFile(jar) as archive:
            for member in archive.infolist():
                if member.is_dir() or not is_notice(member.filename, include_readmes=True):
                    continue
                if member.file_size > 2_000_000:
                    raise ValueError("Notice exceeds bound")
                raw = archive.read(member)
                fingerprint = digest(raw)
                path = output / "notices" / (fingerprint + ".txt")
                path.parent.mkdir(exist_ok=True)
                if path.exists() and path.read_bytes() != raw:
                    raise ValueError("Notice digest collision")
                path.write_bytes(raw)
                notices.setdefault(fingerprint, {"bytes": len(raw), "file": str(path.relative_to(output)), "origins": []})["origins"].append({"artifact": str(relative), "entry": member.filename})

    def fetch(jar):
        relative, artifact, version = coordinates(jar, repository)
        source_name = artifact + "-" + version + "-sources.jar"
        source_relative = relative.parent / source_name
        url = MAVEN + source_relative.as_posix()
        record = {"binaryArtifact": str(relative), "binarySHA256": digest(jar.read_bytes()), "sourceURL": url}
        try:
            raw = download(url, MAX_SOURCE_BYTES)
            validate_source(raw)
            checksum = download(url + ".sha1", 256).decode("ascii").strip().split()[0].lower()
            if not re.fullmatch(r"[0-9a-f]{40}", checksum) or hashlib.sha1(raw).hexdigest() != checksum:
                raise ValueError("Published source checksum mismatch")
            target = output / "sources" / source_relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
            record.update(status="published-source-retained", sourceFile=str(target.relative_to(output)), sourceBytes=len(raw), sourceSHA256=digest(raw), publishedSHA1=checksum)
        except urllib.error.HTTPError as error:
            record.update(status="source-not-published-at-standard-coordinate" if error.code == 404 else "request-failed", httpStatus=error.code)
        except Exception as error:
            record.update(status="request-or-validation-failed", errorType=type(error).__name__, error=str(error))
        return record

    with ThreadPoolExecutor(max_workers=4) as pool:
        sources = list(pool.map(fetch, jars))
    retained = [r for r in sources if r["status"] == "published-source-retained"]
    report = {"classpathArtifacts": len(jars), "publishedSourceArtifactsRetained": len(retained),
              "sourceArtifacts": sources, "originalNoticeTexts": notices,
              "scope": "Pinned classpath upper-bound materials, not proof of native reachability or complete corresponding source",
              "correspondingSourceComplete": False, "nativeRuntimeSDKSourceCovered": False,
              "resourceSpecificSourceCovered": False, "distributionLicenseApproval": False}
    (output / "MATERIALS.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    package = output / "NativeGrammarSourceMaterials.zip"
    with zipfile.ZipFile(package, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(output.rglob("*")):
            if path.is_file() and path != package:
                info = zipfile.ZipInfo(path.relative_to(output).as_posix(), (1980, 1, 1, 0, 0, 0))
                info.external_attr = 0o100644 << 16
                archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    (output / "PACKAGE.json").write_text(json.dumps({"sha256": digest(package.read_bytes()), "bytes": package.stat().st_size}, indent=2) + "\n")
    print(json.dumps({"classpathArtifacts": len(jars), "retainedSourceArtifacts": len(retained), "unresolved": [r for r in sources if r["status"] != "published-source-retained"], "originalNoticeTexts": len(notices)}, indent=2))
    return 1 if any(r["status"] in ["request-failed", "request-or-validation-failed"] for r in sources) else 0


if __name__ == "__main__":
    raise SystemExit(main())
