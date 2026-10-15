#!/usr/bin/env python3
"""Collect a relocatable local relink kit from an existing verified framework build."""
import argparse
import json
from pathlib import Path
import shutil
from relink_native_kit import relative_path, sha, verify_kit


OPTIONS = {"mac-object", "ios-object", "ios-fallbacks", "graal-home", "ios-runtime", "headers", "resources", "manifest", "output"}
INPUTS = {"mac-object": "objects/macos/grammar.o", "ios-object": "objects/ios/grammar.o",
          "ios-fallbacks": "objects/ios/JvmFuncsFallbacks.o", "graal-home": "runtime/graal",
          "ios-runtime": "runtime/ios", "headers": "headers", "resources": "resources", "manifest": "resources-manifest.json"}


def read_arguments(command):
    if not isinstance(command, list) or not all(isinstance(x, str) for x in command):
        raise ValueError("Invalid recorded framework command")
    try:
        start = next(i for i, value in enumerate(command) if value == "--mac-object")
    except StopIteration:
        raise ValueError("Missing recorded inputs")
    tail = command[start:]
    if len(tail) % 2:
        raise ValueError("Incomplete recorded inputs")
    result = {}
    for option, value in zip(tail[::2], tail[1::2]):
        if not option.startswith("--") or option[2:] not in OPTIONS or option[2:] in result:
            raise ValueError("Unknown or duplicate recorded option")
        result[option[2:]] = Path(value)
    if set(result) != OPTIONS:
        raise ValueError("Missing recorded inputs")
    return result


def publish(files, output, baseline):
    """Validate all explicit inputs before creating an immutable, fresh kit."""
    output = Path(output).absolute()
    if output.exists() or output.is_symlink():
        raise ValueError("Use a fresh kit directory")
    names, records = set(), []
    for source, name, expected in files:
        relative_path(name)
        if name.casefold() in names or name.casefold() == "manifest.json":
            raise ValueError("Duplicate or reserved kit path")
        names.add(name.casefold())
        source = Path(source).absolute()
        if source.is_symlink() or not source.is_file() or any(p.is_symlink() for p in source.parents):
            raise ValueError("Input must be a regular file without symlink ancestors: " + name)
        fingerprint = sha(source)
        if expected is not None and fingerprint != expected:
            raise ValueError("Input differs from retained receipt: " + name)
        records.append({"path": name, "bytes": source.stat().st_size, "sha256": fingerprint})
    output.mkdir(parents=True)
    for (source, name, _), record in zip(files, records):
        destination = output / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        with Path(source).open("rb") as incoming, destination.open("xb") as outgoing:
            shutil.copyfileobj(incoming, outgoing, 1024 * 1024)
        if destination.stat().st_size != record["bytes"] or sha(destination) != record["sha256"]:
            raise ValueError("Input changed while copying: " + name)
    manifest = {"schema": 1, "kind": "scriptum-native-relink-kit", "inputs": INPUTS,
                "files": sorted(records, key=lambda x: x["path"]), "baseline": baseline,
                "distributionApproved": False, "completeCorrespondingSource": False,
                "scope": "Local offline relink inputs; full source rebuild, source redistribution review and application installation remain separate."}
    with (output / "MANIFEST.json").open("x") as stream:
        json.dump(manifest, stream, indent=2); stream.write("\n")
    return manifest


def collect(command_path, state_path, tools):
    args = read_arguments(json.loads(command_path.read_text()))
    state = json.loads(state_path.read_text())
    if state.get("packaged") is not True:
        raise ValueError("Framework package is not verified")
    files = []
    def add(path, name, fingerprint=None):
        files.append((path, name, fingerprint))
    for platform, key in (("macos", "mac-object"), ("ios", "ios-object")):
        add(args[key], INPUTS[key], state["artifacts"][platform]["nativeObjectSHA256"])
    # Earlier STATE lacks a fallback-object fingerprint. Bind its current bytes
    # explicitly, retain the generated source, and do not claim prior attestation.
    add(args["ios-fallbacks"], INPUTS["ios-fallbacks"])
    add(args["ios-fallbacks"].with_suffix(".c"), "sources/generated/JvmFuncsFallbacks.c")
    graal = args["graal-home"]
    libraries = ["java", "nio", "zip", "net", "prefs", "j2pkcs11", "fdlibm", "extnet", "jvm", "libchelper", "darwin"]
    for platform in ("macos", "ios"):
        support_relative = "lib/svm/clibraries/" + ("darwin-aarch64" if platform == "macos" else "27/ios-arm64")
        support = graal / support_relative
        runtime = graal / "lib/static/darwin-aarch64" if platform == "macos" else args["ios-runtime"]
        for library in libraries + (["jaas", "ffi"] if platform == "ios" else []):
            name = "lib" + library + ".a"
            # Preserve the exact -L search precedence in build_frameworks.py.
            source = support / name if (support / name).is_file() else runtime / name
            expected = state["runtimeLibraries"][platform].get(str(source))
            if expected is None:
                raise ValueError("Runtime archive has no retained fingerprint: " + name)
            destination = "runtime/graal/" + str(source.relative_to(graal)) if source.is_relative_to(graal) else "runtime/ios/" + name
            add(source, destination, expected)
    header_paths = [(args["headers"] / "graal_isolate.h", "headers/graal_isolate.h")]
    for path in ("include/jni.h", "include/darwin/jni_md.h", "lib/svm/clibraries/darwin-aarch64/include/aarch64cpufeatures.h"):
        header_paths.append((graal / path, "runtime/graal/" + path))
    for source, destination in header_paths:
        add(source, destination, state["abiHeaderSHA256"][str(source)])
    add(args["manifest"], INPUTS["manifest"], state["resourceManifestSHA256"])
    resources = json.loads(args["manifest"].read_text())["resources"]
    for record in resources:
        relative_path(record["path"])
        add(args["resources"] / record["path"], "resources/" + record["path"], record["sha256"])
    for name in ("build_frameworks.py", "IOSRuntimeCompatibility.c", "IOSRuntimeCompatibility-LICENSE.txt"):
        add(tools / name, "tools/" + name, state["sourceSHA256"][name])
    add(tools / "relink_native_kit.py", "relink_native_kit.py")
    add(tools / "NativeRelinkKit.md", "README.md")
    baseline = {"frameworkStateSHA256": sha(state_path), "recordedCommandSHA256": sha(command_path),
                "nativeObjectSHA256": {p: state["artifacts"][p]["nativeObjectSHA256"] for p in ("macos", "ios")},
                "fallbackObjectScope": "Current local bytes and generated source retained; the prior framework receipt did not fingerprint this input.",
                "resourceManifestSHA256": state["resourceManifestSHA256"]}
    return files, baseline


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--framework-command", type=Path, required=True)
    parser.add_argument("--framework-state", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    files, baseline = collect(args.framework_command, args.framework_state, Path(__file__).resolve().parent)
    publish(files, args.output, baseline)
    manifest = verify_kit(args.output)
    print(json.dumps({"files": len(manifest["files"]), "kitManifestSHA256": sha(args.output / "MANIFEST.json"), "integrityVerified": True, "distributionApproved": False}, indent=2))


if __name__ == "__main__":
    main()
