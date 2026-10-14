#!/usr/bin/env python3
"""Build isolated Apple framework candidates; never enables an application route."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import subprocess

NAME = "ScriptumGrammar"
EXPORTS = ["graal_create_isolate", "graal_attach_thread", "graal_get_current_thread",
           "graal_get_isolate", "graal_detach_thread", "graal_tear_down_isolate",
           "graal_detach_all_threads_and_tear_down_isolate", "scriptum_quality_set_heap_limit",
           "scriptum_quality_set_resource_root", "scriptum_quality_check", "vmLocatorSymbol"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resource_records(root, manifest):
    values = manifest["resources"]
    seen = set()
    for record in values:
        name = record["path"]
        path = PurePosixPath(name)
        if not name or path.as_posix() != name or path.is_absolute() or ".." in path.parts or "\\" in name or name in seen:
            raise ValueError("Unsafe or duplicate resource path")
        seen.add(name)
        target = root.joinpath(*path.parts)
        cursor = root
        for part in path.parts:
            cursor = cursor / part
            if cursor.is_symlink():
                raise ValueError("Resource path contains a symlink")
        if target.is_symlink() or not target.resolve().is_relative_to(root):
            raise ValueError("Resource leaves its verified root")
        if not target.is_file() or target.stat().st_size != record["bytes"] or sha(target) != record["sha256"]:
            raise ValueError("Resource bytes differ: " + name)
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mac-object", type=Path, required=True)
    parser.add_argument("--ios-object", type=Path, required=True)
    parser.add_argument("--ios-fallbacks", type=Path, required=True)
    parser.add_argument("--graal-home", type=Path, required=True)
    parser.add_argument("--ios-runtime", type=Path, required=True)
    parser.add_argument("--headers", type=Path, required=True)
    parser.add_argument("--resources", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        raise ValueError("Use a fresh output directory")
    root = args.resources.resolve()
    manifest = json.loads(args.manifest.read_text())
    records = resource_records(root, manifest)
    output.mkdir(parents=True)
    commands, artifacts, runtime_archives = [], {}, {}

    def run(command, log_name):
        commands.append(command)
        (output / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")
        with (output / log_name).open("wb") as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)

    exports = output / "exports.txt"
    exports.write_text("\n".join("_" + name for name in EXPORTS) + "\n")
    graal = args.graal_home.resolve()
    ios_runtime = args.ios_runtime.resolve()
    mac_runtime = graal / "lib/static/darwin-aarch64"
    libraries = ["java", "nio", "zip", "net", "prefs", "j2pkcs11", "fdlibm", "extnet", "jvm"]
    for platform, object_path in [("macos", args.mac_object), ("ios", args.ios_object)]:
        framework = output / platform / (NAME + ".framework")
        framework.mkdir(parents=True)
        if platform == "macos":
            contents = framework / "Versions/A"
            contents.mkdir(parents=True)
        else:
            contents = framework
        headers, modules = contents / "Headers", contents / "Modules"
        headers.mkdir(); modules.mkdir()
        shutil.copy2(args.headers / "graal_isolate.h", headers / "graal_isolate.h")
        (headers / (NAME + ".h")).write_text('''#ifndef SCRIPTUM_GRAMMAR_H
#define SCRIPTUM_GRAMMAR_H
#include "graal_isolate.h"
#ifdef __cplusplus
extern "C" {
#endif
int scriptum_quality_set_heap_limit(graal_isolatethread_t*, long long int);
int scriptum_quality_set_resource_root(graal_isolatethread_t*, char*, int);
int scriptum_quality_check(graal_isolatethread_t*, char*, int, char*, int, char*, int);
#ifdef __cplusplus
}
#endif
#endif
''')
        (modules / "module.modulemap").write_text('framework module ' + NAME + ' {\n  umbrella header "' + NAME + '.h"\n  export *\n}\n')
        info = {"CFBundleIdentifier": "com.mobilebox.ScriptumGrammar", "CFBundleName": NAME,
                "CFBundleExecutable": NAME, "CFBundlePackageType": "FMWK", "CFBundleVersion": "6.6",
                "CFBundleShortVersionString": "6.6", "CFBundleSupportedPlatforms": ["MacOSX" if platform == "macos" else "iPhoneOS"]}
        info_path = contents / "Resources/Info.plist" if platform == "macos" else contents / "Info.plist"
        info_path.parent.mkdir(exist_ok=True)
        info_path.write_bytes(plistlib.dumps(info))
        if platform == "ios":
            license_directory = contents / "Resources/Licenses"
            license_directory.mkdir(parents=True)
            shutil.copy2(Path(__file__).resolve().parent / "IOSRuntimeCompatibility-LICENSE.txt",
                         license_directory / "IOSRuntimeCompatibility.txt")
        binary = contents / NAME
        if platform == "macos":
            (framework / "Versions/Current").symlink_to("A")
            for name in ["Headers", "Modules", "Resources", NAME]:
                (framework / name).symlink_to("Versions/Current/" + name)
            target, sdk = "arm64-apple-macos27.0", "macosx"
            support = graal / "lib/svm/clibraries/darwin-aarch64"
            runtime = mac_runtime
            install_name = "@rpath/" + NAME + ".framework/Versions/A/" + NAME
        else:
            target, sdk = "arm64-apple-ios27.0", "iphoneos"
            support = graal / "lib/svm/clibraries/27/ios-arm64"
            runtime = ios_runtime
            install_name = "@rpath/" + NAME + ".framework/" + NAME
        sdk_path = subprocess.check_output(["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True).strip()
        command = ["xcrun", "clang", "-dynamiclib", "-target", target, "-isysroot", sdk_path,
                   str(object_path.resolve())]
        # The library has no UIApplication delegate or executable main. Only
        # the generated JVM fallback functions accompany the iOS native object.
        if platform == "ios":
            compatibility_source = Path(__file__).resolve().parent / "IOSRuntimeCompatibility.c"
            compatibility_object = output / "IOSRuntimeCompatibility.o"
            run(["xcrun", "clang", "-c", "-target", target, "-isysroot", sdk_path, "-Wall", "-Wextra", "-Werror",
                 "-I", str(graal / "include"), "-I", str(graal / "include/darwin"),
                 "-I", str(graal / "lib/svm/clibraries/darwin-aarch64/include"),
                 str(compatibility_source), "-o", str(compatibility_object)], "ios-compatibility-build.log")
            command += [str(args.ios_fallbacks.resolve()), str(compatibility_object)]
        command += ["-L" + str(support), "-L" + str(runtime)]
        command += ["-l" + name for name in libraries]
        if platform == "ios":
            command += ["-ljaas", "-lffi"]
        command += ["-llibchelper", "-ldarwin", "-lpthread", "-lz", "-ldl", "-lc++",
                    "-framework", "Foundation", "-framework", "CoreFoundation", "-framework", "CFNetwork",
                    "-Wl,-install_name," + install_name, "-Wl,-exported_symbols_list," + str(exports),
                    "-Wl,-map," + str(output / (platform + "-link.map")), "-o", str(binary)]
        run(command, platform + "-link.log")
        run(["codesign", "--force", "--sign", "-", str(framework)], platform + "-sign.log")
        run(["codesign", "--verify", "--strict", str(framework)], platform + "-signature-verify.log")
        symbols = subprocess.check_output(["xcrun", "nm", "-gUj", str(binary)], text=True).splitlines()
        if set(symbols) != {"_" + name for name in EXPORTS}:
            raise ValueError("Unexpected framework exports: " + repr(symbols))
        for tool, flags in [("otool", ["-L"]), ("vtool", ["-show-build"])]:
            run(["xcrun", tool, *flags, str(binary)], platform + "-" + tool + ".log")
        artifacts[platform] = {"binarySHA256": sha(binary), "binaryBytes": binary.stat().st_size,
                               "nativeObjectSHA256": sha(object_path), "exports": symbols}
        runtime_archives[platform] = {str(p): sha(p) for parent in [support, runtime] for p in sorted(parent.glob("*.a"))}

    # Raw, byte-verified resources are copied once. No bundled transfer ZIP or
    # extracted runtime cache is created.
    bundle = output / "ScriptumGrammarResources.bundle"
    bundle.mkdir()
    (bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.mobilebox.ScriptumGrammarResources",
        "CFBundleName": "ScriptumGrammarResources", "CFBundlePackageType": "BNDL", "CFBundleVersion": "6.6"}))
    shutil.copy2(args.manifest, bundle / "manifest.json")
    for record in records:
        target = bundle.joinpath(*PurePosixPath(record["path"]).parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / record["path"], target)
    resource_records(bundle, manifest)
    run(["xcodebuild", "-create-xcframework", "-framework", str(output / "macos" / (NAME + ".framework")),
         "-framework", str(output / "ios" / (NAME + ".framework")), "-output", str(output / (NAME + ".xcframework"))], "xcframework.log")
    state = {"packaged": True, "artifacts": artifacts, "resourceFiles": len(records),
             "resourceRawBytes": sum(r["bytes"] for r in records), "resourceManifestSHA256": sha(args.manifest),
             "runtimeLibraries": runtime_archives,
             "architectures": {"macos": ["arm64"], "ios": ["arm64"]}, "simulatorSlice": False,
             "applicationRouteEnabled": False, "runtimeExecutionVerified": False,
             "distributionLicenseApproval": False, "signature": "ad-hoc local candidate only"}
    state["sourceSHA256"] = {name: sha(Path(__file__).resolve().parent / name) for name in [
        "build_frameworks.py", "IOSRuntimeCompatibility.c", "IOSRuntimeCompatibility-LICENSE.txt"]}
    state["abiHeaderSHA256"] = {str(path): sha(path) for path in [
        args.headers / "graal_isolate.h", graal / "include/jni.h", graal / "include/darwin/jni_md.h",
        graal / "lib/svm/clibraries/darwin-aarch64/include/aarch64cpufeatures.h"]}
    (output / "STATE.json").write_text(json.dumps(state, indent=2) + "\n")
    print(json.dumps({k: v for k, v in state.items() if k != "runtimeLibraries"}, indent=2))


if __name__ == "__main__":
    main()
