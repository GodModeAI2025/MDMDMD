#!/usr/bin/env python3
"""Build isolated experimental source XCFramework; never edit production manifest.
Requires official Rust1.98.1 and preinstalled arm64 macOS/iOS/simulator targets.
Output replaces ONLY this fork's generated XCFramework.
"""
import hashlib, json, os, pathlib, shutil, subprocess, sys
root=pathlib.Path(__file__).resolve().parents[2]
fork=root/'Vendor'/'automerge-swift-0.7.2'
output=fork/'automergeFFI.xcframework'
cargo=shutil.which('cargo') or str(pathlib.Path.home()/'.cargo/bin/cargo')
env=dict(os.environ); env['PATH']=str(pathlib.Path(cargo).parent)+os.pathsep+env.get('PATH','')
env['CARGO_HOME']=env.get('SCRIPTUM_CARGO_CACHE','/private/tmp/scriptum-bounded-cargo')
env['CARGO_TARGET_DIR']=env.get('SCRIPTUM_RUST_BUILD','/private/tmp/scriptum-bounded-fork-target')
version=subprocess.check_output(['rustc','--version'],env=env,text=True).strip()
if version != 'rustc 1.98.1 (48a229cea 2026-09-01)': raise SystemExit('Exact compiler required: '+version)
manifest=fork/'rust/Cargo.toml'; targets=['aarch64-apple-darwin','aarch64-apple-ios','aarch64-apple-ios-sim']
for target in targets:
    subprocess.run([cargo,'build','--manifest-path',str(manifest),'--target',target,'--locked','--release'],env=env,check=True)
headers=fork/'Sources/_CAutomergeUniffi/include'
if output.exists(): shutil.rmtree(output)
command=['xcodebuild','-create-xcframework']
for target in targets: command += ['-library',str(pathlib.Path(env['CARGO_TARGET_DIR'])/target/'release/libuniffi_automerge.a'),'-headers',str(headers)]
subprocess.run(command+['-output',str(output)],env=env,check=True)
checksums={str(p.relative_to(output)):hashlib.sha256(p.read_bytes()).hexdigest() for p in output.rglob('*.a')}
print(json.dumps(dict(compiler=version,targets=targets,archiveChecksums=checksums),indent=2))
