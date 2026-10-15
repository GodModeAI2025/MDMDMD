#!/usr/bin/env python3
"""Read-only JAR/TAR verification; no extraction or execution of upstream code.

Writes evidence to a new directory. This is resource/source correspondence,
not a legal determination or a complete preferred-source reconstruction.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile
import zipfile

PACKAGE = Path(__file__).resolve().parent.parent
JAR_HASH = "3ff49f9b989e3c50eb8d96f4385906b3562b638607aeeddaffd90939695b66a5"
RESOURCE_ROOT = "distr/morfologik-ukrainian/src/main/resources/"
GENERATED = {
    "org/languagetool/resource/uk/ukrainian.dict": "prepareDict -> POSDictionaryBuilder; out/dict_corp_lt.txt",
    "org/languagetool/resource/uk/ukrainian_synth.dict": "prepareDict synthesis filter -> SynthDictionaryBuilder; out/dict_corp_lt.txt",
    "org/languagetool/resource/uk/ukrainian_synth.dict_tags.txt": "SynthDictionaryBuilder side output; filtered out/dict_corp_lt.txt",
    "org/languagetool/resource/uk/ukrainian_tags.txt": "tagList; third column of out/dict_corp_lt.txt; sort -u",
    "org/languagetool/resource/uk/hunspell/uk_UA.dict": "prepareSpellWords -> SpellDictionaryBuilder; out/words_spell.txt + uk_wordlist.xml",
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def valid_name(name):
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or "\\" in name:
        raise ValueError(f"unsafe archive name: {name}")


def read_source(commit, path, expected):
    assert sha(path.read_bytes()) == expected, path
    root = "dict_uk-" + commit + "/"
    source = {}
    seen = set()
    with tarfile.open(path, "r:gz") as archive:
        members = archive.getmembers()
        assert len(members) < 2000 and sum(x.size for x in members) < 50_000_000
        for member in members:
            valid_name(member.name)
            assert member.name not in seen, member.name
            seen.add(member.name)
            assert member.isdir() or member.isfile(), member.name
            if member.isfile():
                assert member.name.startswith(root), member.name
                source[member.name[len(root):]] = archive.extractfile(member).read()
    return source


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work-root", type=Path, required=True,
                        help="Local work root containing the original pinned archives/JAR")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output
    work = args.work_root.resolve()
    jar = work / "native-quality-aot-20261014/m2/ua/net/nlp/morfologik-ukrainian-lt/6.6.0/morfologik-ukrainian-lt-6.6.0.jar"
    sources_to_read = [
        ("4787f7acbed642584697ff7ccd772fafa5de1f31",
         work / "native-quality-data-review-20261015/Ukrainian-6.6.0-candidate.tar.gz",
         "31abd7ea4239a611a007f053f6a06bfed951d3ed2b4de0fa672c6481537e9abf"),
        ("8eb833b901bb77798d6f37e213880db10c462c87",
         work / "native-ukrainian-source-20261015/release-period-last-source.tar.gz",
         "cd91fe4fa5bfab44ad12b4338ac7fd532d28c793a5e6fd40c8176bff0073360f"),
    ]
    assert not output.exists(), "Output must be a new directory"
    jar_bytes = jar.read_bytes()
    assert sha(jar_bytes) == JAR_HASH
    assert (PACKAGE / "upstream/maven/release-jar.sha256").read_text().strip() == JAR_HASH
    module = json.loads((PACKAGE / "upstream/maven/release.module").read_text())
    assert all(v["files"][0]["sha256"] == JAR_HASH for v in module["variants"])
    with zipfile.ZipFile(jar) as archive:
        infos = archive.infolist()
        assert len({x.filename for x in infos}) == len(infos), "Duplicate ZIP member"
        assert sum(x.file_size for x in infos) < 20_000_000
        for info in infos:
            valid_name(info.filename)
        resources = {x.filename: archive.read(x) for x in infos if not x.is_dir() and not x.filename.startswith("META-INF/")}
        manifest = archive.read("META-INF/MANIFEST.MF")
    assert len(resources) == 17
    result = {"scope": "Technical source correspondence; not legal or release approval", "jar": str(jar), "jarSHA256": JAR_HASH,
              "mavenChecksumMatches": True, "mavenModuleChecksumMatches": True, "candidates": []}
    sources = {}
    for commit, archive_path, expected in sources_to_read:
        source = read_source(commit, archive_path, expected)
        sources[commit] = source
        build = source["distr/morfologik-ukrainian/build.gradle"].decode()
        # This mapping follows upstream processResources, not name coincidence.
        for snippet in ['String semtagsDir="$projectDir/../../data/sem"', 'from semtagsDir', '/ua/net/nlp/dict_uk/semtags', "include '*.csv'", 'from versionFile']:
            assert snippet in build, snippet
        rows = []
        for name, data in resources.items():
            row = {"jarResource": name, "bytes": len(data), "sha256": sha(data)}
            if name.startswith("ua/net/nlp/dict_uk/semtags/"):
                path = "data/sem/" + name.rsplit("/", 1)[1]
                kind = "processResources semantic CSV copy"
            elif name.endswith("/VERSION"):
                path, kind = "VERSION", "processResources root VERSION copy"
            else:
                path, kind = RESOURCE_ROOT + name, "resources directory copy"
            row.update(sourcePath=path, mapping=kind)
            if path in source:
                row.update(sourceSHA256=sha(source[path]), bytesEqual=(data == source[path]))
                row["status"] = "exact" if row["bytesEqual"] else "mismatch"
                if path == "VERSION":
                    row.update(sourceText=source[path].decode(), jarText=data.decode())
            else:
                assert name in GENERATED, name
                row.update(status="generated-not-rebuilt", declaredGeneration=GENERATED[name])
            rows.append(row)
        result["candidates"].append({"commit": commit, "archive": str(archive_path), "archiveSHA256": expected,
                                     "exactResources": sum(r["status"] == "exact" for r in rows),
                                     "mismatchedResources": sum(r["status"] == "mismatch" for r in rows),
                                     "generatedNotRebuilt": sum(r["status"] == "generated-not-rebuilt" for r in rows),
                                     "resources": rows})
    output.mkdir()
    for commit, source in sources.items():
        dest = output / commit
        dest.mkdir()
        selected = ["README.md", "VERSION", "build.gradle", "settings.gradle", "publish.sh", "do_all.sh", "gradle/wrapper/gradle-wrapper.properties",
                    "distr/morfologik-ukrainian/README.md", "distr/morfologik-ukrainian/build.gradle",
                    "distr/morfologik-ukrainian/settings.gradle",
                    RESOURCE_ROOT + "org/languagetool/resource/uk/README", RESOURCE_ROOT + "org/languagetool/resource/uk/hunspell/README.txt"]
        for path in selected:
            if path in source:
                target = dest / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(source[path])
        manifest_rows = [{"path": name, "bytes": len(data), "sha256": sha(data)} for name, data in sorted(source.items())]
        (dest / "ARCHIVE_FILES.json").write_text(json.dumps(manifest_rows, indent=2) + "\n")
    (output / "jar-manifest.txt").write_bytes(manifest)
    for path in ("org/languagetool/resource/uk/README", "org/languagetool/resource/uk/hunspell/README.txt"):
        (output / ("jar-" + ("hunspell-" if "/hunspell/" in path else "") + "README.txt")).write_bytes(resources[path])
    (output / "SOURCE_BINDING.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"jarSHA256": JAR_HASH, "candidates": [{k: c[k] for k in ("commit", "exactResources", "mismatchedResources", "generatedNotRebuilt")} for c in result["candidates"]]}, indent=2))


if __name__ == "__main__":
    main()
