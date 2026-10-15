#!/usr/bin/env python3
"""Generate an isolated local app candidate from verified native framework inputs.

Does not change the normal project, install an app or upload a build. Native
source/distribution obligations remain separate from this integration probe.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as XML


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--framework-package", type=Path, required=True)
    parser.add_argument("--qa-root", type=Path, required=True,
                        help="Dedicated new QA library in the app's sandbox; never a personal library")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    package = args.framework_package.resolve(strict=True)
    output = args.output.resolve()
    qa_root = args.qa_root.expanduser().resolve()
    if output.exists() or qa_root.exists():
        raise ValueError("Use fresh candidate and QA-library directories")
    if "/Containers/com.mobilebox.Skriptum/Data/tmp/" not in str(qa_root):
        raise ValueError("QA library must be inside Scriptum's dedicated sandbox temporary directory")
    state = json.loads((package / "STATE.json").read_text())
    manifest = package / "ScriptumGrammarResources.bundle/manifest.json"
    if not state.get("packaged") or sha(manifest) != state["resourceManifestSHA256"]:
        raise ValueError("Unverified framework/resource package")
    for platform in ["macos", "ios"]:
        if sha(package / platform / "ScriptumGrammar.framework/ScriptumGrammar") != state["artifacts"][platform]["binarySHA256"]:
            raise ValueError("Framework differs from package receipt: " + platform)
    targets = {}
    for name, platform, entitlement, info in [
        ("SkriptumMac", "macos", "Config/SkriptumMac.entitlements", "Config/Info-Mac.plist"),
        ("Skriptum", "ios", "Skriptum.entitlements", "Config/Info.plist"),
    ]:
        targets[name] = {
            "sources": [{"path": str(package / "ScriptumGrammarResources.bundle"), "type": "folder", "buildPhase": "resources"}],
            "dependencies": [{"framework": str(package / platform / "ScriptumGrammar.framework"), "embed": True, "codeSign": True}],
            "settings": {"base": {"CODE_SIGN_ENTITLEMENTS": str(repo / entitlement), "INFOPLIST_FILE": str(repo / info)}},
        }
    spec = {"include": [{"path": str(repo / "project.yml"), "relativePaths": True}],
            "name": "ScriptumNativeQualityCandidate", "targets": targets}
    output.mkdir(parents=True)
    spec_path = output / "candidate-spec.json"
    spec_path.write_text(json.dumps(spec, indent=2) + "\n")
    # Added absolute paths are re-expressed relative to project-root by
    # XcodeGen, so project-root must be the generated project's own directory.
    command = ["xcodegen", "generate", "--spec", str(spec_path), "--project-root", str(output), "--project", str(output)]
    subprocess.run(command, check=True)
    project = output / "ScriptumNativeQualityCandidate.xcodeproj"
    scheme = project / "xcshareddata/xcschemes/SkriptumMac.xcscheme"
    tree = XML.parse(scheme)
    launch = tree.getroot().find("LaunchAction")
    for previous in launch.findall("CommandLineArguments"):
        launch.remove(previous)
    arguments = XML.SubElement(launch, "CommandLineArguments")
    for argument in ["--scriptum-mac-qa-root", str(qa_root)]:
        XML.SubElement(arguments, "CommandLineArgument", {"argument": argument, "isEnabled": "YES"})
    tree.write(scheme, encoding="utf-8", xml_declaration=True)
    (output / "CANDIDATE.json").write_text(json.dumps({
        "project": str(project), "qaRoot": str(qa_root), "generationCommand": command,
        "frameworkPackageStateSHA256": sha(package / "STATE.json"), "appInstalled": False,
        "uploaded": False, "distributionApproved": False,
        "scope": "Local arm64 integration candidate, not a distribution-ready dependency package",
    }, indent=2) + "\n")
    print(project)


if __name__ == "__main__":
    main()
