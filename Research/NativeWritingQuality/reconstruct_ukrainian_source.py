#!/usr/bin/env python3
"""Isolated, pinned dict_uk reconstruction; never claims original release identity.

No downloads, Gradle plugins, installation, publishing, or application changes.
Prepare compiles unchanged upstream sources and runs the documented prerequisites.
Expand uses a bounded JVM and omits only optional visual/statistics output.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tarfile
import time

COMMIT = "8eb833b901bb77798d6f37e213880db10c462c87"
ARCHIVE_SHA256 = "cd91fe4fa5bfab44ad12b4338ac7fd532d28c793a5e6fd40c8176bff0073360f"
DEPENDENCIES = {
    "groovy-4.0.26.jar": "ae3196ed31fa11e8506f9c40a6b34fdaff06a8eeda78a8a6ebaeb1a2a0ad35dc",
    "groovy-cli-picocli-4.0.26.jar": "c77d80d796e5459cedc284bb5644594ac384590ff772dab43aa543aff76cebb4",
    "picocli-4.7.6.jar": "ed441183f309b93f104ca9e071e314a4062a893184e18a3c7ad72ec9cba12ba0",
    "commons-cli-1.4.jar": "fd3c7c9545a9cdb2051d1f9155c4f76b1e4ac5a57304404a6eedb578ffba7328",
    "slf4j-api-2.0.16.jar": "a12578dde1ba00bd9b816d388a0b879928d00bab3c83c240f7013bf4196c579a",
    "slf4j-simple-2.0.16.jar": "effc32018658bea09d1e08c7d1060ccad46c086960f583d07dd7ffe9c1172a47",
}


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def inventory(root):
    return {str(p.relative_to(root)): sha(p) for p in sorted(root.rglob("*")) if p.is_file()}


def extract_source(archive_path, destination):
    if sha(archive_path) != ARCHIVE_SHA256:
        raise ValueError("Unpinned source archive")
    if destination.exists():
        raise ValueError("Source destination already exists")
    with tarfile.open(archive_path, "r:gz") as archive:
        members = archive.getmembers()
        if len(members) > 2000 or sum(m.size for m in members) > 50_000_000:
            raise ValueError("Archive exceeds bound")
        seen = set()
        for member in members:
            p = PurePosixPath(member.name)
            if p.is_absolute() or ".." in p.parts or "\\" in member.name or member.name in seen:
                raise ValueError("Unsafe or duplicate archive member")
            seen.add(member.name)
            if not (member.isdir() or member.isfile()) or p.parts[0] != "dict_uk-" + COMMIT:
                raise ValueError("Unexpected archive member type/root")
        destination.mkdir()
        for member in members:
            if member.isfile():
                target = destination.joinpath(*PurePosixPath(member.name).parts[1:])
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.extractfile(member).read())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--phase", choices=("prepare", "expand"), required=True)
    args = parser.parse_args()
    work, output = args.work_root.resolve(), args.output.resolve()
    research = work / "native-ukrainian-source-20261015"
    dependencies = research / "reconstruction/dependencies"
    java_home = work / "native-quality-aot-20261014/graalvm-svm-java17-darwin-m1-gluon-22.1.0.1-Final/Contents/Home"
    java = java_home / "bin/java"
    jars = [dependencies / name for name in DEPENDENCIES]
    for jar in jars:
        if sha(jar) != DEPENDENCIES[jar.name]:
            raise ValueError("Unpinned dependency: " + str(jar))
    source, classes = output / "source", output / "classes"
    if args.phase == "prepare":
        if output.exists():
            raise ValueError("Prepare requires a fresh output directory")
        output.mkdir(parents=True)
        extract_source(research / "release-period-last-source.tar.gz", source)
        classes.mkdir()
        (output / "tmp").mkdir()
    else:
        previous = json.loads((output / "prepare.json").read_text())
        if previous["sourceAfter"] != inventory(source) or previous["classes"] != inventory(classes):
            raise ValueError("Prepared source/classes changed")
    if (source / "VERSION").read_bytes() != b"6.6.0-SNAPSHOT\n":
        raise ValueError("Source VERSION must remain unchanged")
    before = inventory(source)
    cp = os.pathsep.join(map(str, [*jars, classes, source / "src/main/resources"]))
    env = dict(os.environ, JAVA_HOME=str(java_home))
    steps = []

    def run(name, main_class, argv, *, heap=768, cwd=source, timeout=90):
        command = [str(java), "-Xms128m", f"-Xmx{heap}m", "-XX:ActiveProcessorCount=2",
                   "-Dfile.encoding=UTF-8", "-Dgroovy.grape.enable=false",
                   "-Djava.io.tmpdir=" + str(output / "tmp"), "-cp", cp, main_class, *map(str, argv)]
        stdout, stderr = output / (name + ".stdout"), output / (name + ".stderr")
        if stdout.exists() or stderr.exists():
            raise ValueError("Step output already exists: " + name)
        start = time.monotonic()
        print("Running " + name, flush=True)
        with stdout.open("xb") as out, stderr.open("xb") as err:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=out, stderr=err, timeout=timeout)
        step = {"name": name, "argv": command, "cwd": str(cwd), "timeoutSeconds": timeout,
                "exitCode": result.returncode, "seconds": time.monotonic() - start,
                "stdoutSHA256": sha(stdout), "stderrSHA256": sha(stderr)}
        steps.append(step)
        (output / (args.phase + "-steps.json")).write_text(json.dumps(steps, indent=2) + "\n")
        if result.returncode:
            raise RuntimeError(f"{name} failed ({result.returncode}); inspect {stderr}")

    if args.phase == "prepare":
        sources = sorted((source / "src/main/java").rglob("*.java")) + sorted((source / "src/main/groovy").rglob("*.groovy"))
        run("compile", "org.codehaus.groovy.tools.FileSystemCompiler",
            ["--classpath", cp, "--jointCompilation", "-d", classes, *sources])
        for suffix in ("", "_advp"):
            run("reverse" + suffix, "org.dict_uk.expand.VerbReverse",
                [source / f"data/affix/v{suffix}.aff", source / f"data/affix/vr{suffix}.aff"])
        run("autogen", "org.dict_uk.tools.Autogen",
            ["data/dict/base.lst", "data/dict/base-compound.lst", "data/dict/base-compound_1992.lst", "data/dict/base-autogen.lst"])
    else:
        run("expand", "org.dict_uk.expand.ExpandAll",
            ["--aff", source / "data/affix", "--dict", source / "data/dict", "--mfl", "--wordlist", "--time"],
            heap=4096, cwd=source / "out", timeout=600)
        for name in ("dict_corp_lt.txt", "words_spell.txt", "words.txt"):
            if not (source / "out" / name).is_file() or (source / "out" / name).stat().st_size == 0:
                raise ValueError("Missing expansion output: " + name)
    if (source / "VERSION").read_bytes() != b"6.6.0-SNAPSHOT\n":
        raise ValueError("Upstream source VERSION changed")
    receipt = {"scope": "Pinned source reconstruction configuration, not the original release build",
               "sourceCommit": COMMIT, "sourceArchiveSHA256": ARCHIVE_SHA256,
               "runnerSHA256": sha(Path(__file__)), "javaSHA256": sha(java), "dependencies": DEPENDENCIES,
               "sourceVersion": "6.6.0-SNAPSHOT", "sourceBefore": before, "sourceAfter": inventory(source),
               "classes": inventory(classes), "steps": steps,
               "releaseGeneratorVersionKnown": False,
               "spellingFrequencySourcePresent": (source / "distr/morfologik-ukrainian/src/main/data/uk_wordlist.xml").is_file()}
    (output / (args.phase + ".json")).write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({"phase": args.phase, "steps": len(steps), "status": "completed", "sourceVersion": receipt["sourceVersion"]}), flush=True)


if __name__ == "__main__":
    main()
