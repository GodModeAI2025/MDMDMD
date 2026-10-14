#!/usr/bin/env python3
"""Exercise the real C driver through the app's Swift reviewer and decoder."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--headers", type=Path)
    libraries = parser.add_mutually_exclusive_group(required=True)
    libraries.add_argument("--library-directory", type=Path)
    libraries.add_argument("--framework", type=Path)
    parser.add_argument("--resources", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--scratch", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--native-receipt", type=Path, required=True)
    args = parser.parse_args()
    research = Path(__file__).resolve().parent
    repo = research.parents[1]
    evidence = repo / "docs/qa-native-resource-pack-20261015"
    manifest = json.loads((evidence / "manifest.json").read_text())
    root = args.resources.resolve()
    for resource in manifest["resources"]:
        path = PurePosixPath(resource["path"])
        if path.is_absolute() or ".." in path.parts:
            raise ValueError("Invalid manifest path")
        target = root.joinpath(*path.parts)
        if not target.resolve().is_relative_to(root) or target.is_symlink():
            raise ValueError("Resource leaves verified root")
        if target.stat().st_size != resource["bytes"] or sha(target) != resource["sha256"]:
            raise ValueError("Resource bytes differ: " + resource["path"])
    if args.framework:
        framework = args.framework.resolve()
        library = framework / framework.stem
        compile_flags = ["-F", str(framework.parent)]
        link_flags = ["-F", str(framework.parent), "-framework", framework.stem,
                      "-Xlinker", "-rpath", "-Xlinker", str(framework.parent)]
    else:
        if not args.headers:
            parser.error("--headers is required with --library-directory")
        library = args.library_directory.resolve() / "libscriptum_native_quality.dylib"
        header = args.headers.resolve() / "com.mobilebox.research.nativewritingquality.h"
        compile_flags = ["-I", str(header.parent), "-import-objc-header", str(header)]
        link_flags = ["-L", str(library.parent), "-lscriptum_native_quality",
                      "-Xlinker", "-rpath", "-Xlinker", str(library.parent)]
    pinned = json.loads(args.native_receipt.read_text())
    if not pinned.get("passed") or sha(library) != pinned["nativeLibrarySHA256"]:
        raise ValueError("Native library differs from pinned verification")
    output = args.artifacts.resolve()
    output.mkdir(parents=True, exist_ok=False)
    harness = output / "harness"
    sources = harness / "Sources/Probe"
    sources.mkdir(parents=True)
    for name in ["GraalBundledGrammarEngine.swift", "ReviewerIntegrationProbe.swift"]:
        shutil.copy2(research / name, sources / name)
    quote = lambda value: json.dumps(str(value))
    (harness / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "ReviewerProbe", platforms: [.macOS("27.0")],
    dependencies: [.package(path: ''' + quote(repo / "Modules/SkriptumWritingQuality") + ''')],
    targets: [.executableTarget(name: "Probe", dependencies: ["SkriptumWritingQuality"],
        swiftSettings: [.unsafeFlags(''' + json.dumps(compile_flags) + ''')],
        linkerSettings: [.unsafeFlags(''' + json.dumps(link_flags) + ''')])])
''')
    build = ["swift", "build", "--disable-sandbox", "--skip-update", "--cache-path", str(args.cache.resolve()),
             "--scratch-path", str(args.scratch.resolve()), "--package-path", str(harness)]
    commands = [build]
    with (output / "build.log").open("wb") as log:
        subprocess.run(build, stdout=log, stderr=subprocess.STDOUT, check=True)
    executable = args.scratch.resolve() / "debug/Probe"
    command = ["/usr/bin/time", "-l", "/usr/bin/sandbox-exec", "-p",
               "(version 1) (allow default) (deny network*)", str(executable),
               str(research / "Fixtures/GrammarStyleParity.json"), str(root)]
    commands.append(command)
    with (output / "reviewer.json").open("wb") as result, (output / "reviewer.stderr").open("wb") as error:
        completed = subprocess.run(command, stdout=result, stderr=error)
    records = json.loads((output / "reviewer.json").read_text()) if completed.returncode == 0 else []
    passed = completed.returncode == 0 and len(records) == 29 and all(r["findings"] > 0 for r in records)
    source_paths = list((repo / "Modules/SkriptumWritingQuality/Sources").rglob("*.swift"))
    source_paths += [research / name for name in ["GraalBundledGrammarEngine.swift", "ReviewerIntegrationProbe.swift", "verify_reviewer.py"]]
    state = {"passed": passed, "exitCode": completed.returncode, "languageWitnesses": len(records),
             "verifiedResourceFiles": len(manifest["resources"]), "nativeLibrarySHA256": sha(library),
             "outputSHA256": sha(output / "reviewer.json"), "stderrSHA256": sha(output / "reviewer.stderr"),
             "network": "denied during native execution", "appUIIntegrated": False, "iosExecutionProven": False,
             "frameworkModuleImported": args.framework is not None,
             "scope": "Real native host engine through app worker, Markdown projection and correction admission; synthetic witnesses only",
             "sourceSHA256": {str(p.relative_to(repo)): sha(p) for p in sorted(source_paths)}}
    (output / "STATE.json").write_text(json.dumps(state, indent=2) + "\n")
    (output / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")
    print(json.dumps(state, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
