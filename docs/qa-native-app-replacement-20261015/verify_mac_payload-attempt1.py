"""One-shot readback of this local replacement candidate; no install or launch."""
from pathlib import Path
import hashlib
import json
import plistlib
import shutil
import subprocess

base = Path('/Users/markzimmermann/Documents/Codex/2026-10-08/mach/work')
out = base / 'native-quality-app-replacement-20261015'
app = Path('/Users/markzimmermann/Library/Developer/Xcode/DerivedData/ScriptumNativeQualityCandidate-cipawecyyjibgoawjlcybocjrcuy/Build/Products/Debug/Scriptum.app')
package = base / 'native-quality-relink-20261015/relinked-frameworks'
proof = out / 'MAC_APP_PROOF.json'
if proof.exists():
    raise ValueError('Preserve the previous proof; use a fresh output for another run')

def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()

commands = []
for name, command in [
    ('final-mac-app-signature', ['codesign', '--verify', '--deep', '--strict', str(app)]),
    ('mac-app-identity', ['codesign', '-dvv', str(app)]),
    ('mac-framework-identity', ['codesign', '-dvv', str(app / 'Contents/Frameworks/ScriptumGrammar.framework')]),
]:
    result = subprocess.run(command, capture_output=True, text=True)
    (out / (name + '.log')).write_text(result.stdout + result.stderr)
    assert result.returncode == 0, (name, result.stderr)
    commands.append({'name': name, 'command': command, 'exitCode': result.returncode})

source_bundle = package / 'ScriptumGrammarResources.bundle'
bundle = app / 'Contents/Resources/ScriptumGrammarResources.bundle'
manifest = json.loads((source_bundle / 'manifest.json').read_text())
assert sha(bundle / 'manifest.json') == sha(source_bundle / 'manifest.json')
for resource in manifest['resources']:
    path = bundle / resource['path']
    assert not path.is_symlink()
    assert path.stat().st_size == resource['bytes'] and sha(path) == resource['sha256'], resource['path']

comparison = out / 'unsigned-framework-comparison'
comparison.mkdir(exist_ok=False)
frameworks = [package / 'macos/ScriptumGrammar.framework/ScriptumGrammar',
              app / 'Contents/Frameworks/ScriptumGrammar.framework/ScriptumGrammar']
hashes = []
for index, source in enumerate(frameworks):
    path = comparison / ('framework-' + str(index))
    shutil.copyfile(source, path)
    command = ['codesign', '--remove-signature', str(path)]
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    commands.append({'name': 'remove-signature-from-disposable-copy', 'command': command, 'exitCode': result.returncode})
    hashes.append(sha(path))
assert hashes[0] == hashes[1], hashes

info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
debug = executable.with_suffix('.debug.dylib')
result = subprocess.run(['otool', '-L', str(debug)], capture_output=True, text=True)
assert result.returncode == 0
assert '@rpath/ScriptumGrammar.framework/ScriptumGrammar' in result.stdout
(out / 'mac-load-commands.log').write_text(result.stdout)
record = {
    'appPath': str(app), 'executablePath': str(executable), 'debugLibraryPath': str(debug),
    'appExecutableSHA256': sha(executable), 'debugLibrarySHA256': sha(debug),
    'sourceFrameworkSHA256': sha(frameworks[0]), 'embeddedFrameworkSHA256': sha(frameworks[1]),
    'unsignedFrameworksByteEqual': True, 'unsignedFrameworkSHA256': hashes[0],
    'resourceFilesVerified': len(manifest['resources']), 'resourceManifestSHA256': sha(bundle / 'manifest.json'),
    'frameworkDynamicallyLinked': True, 'commands': commands,
    'scope': 'Local newly linked native-framework substitution in development-signed Mac app; no App Store distribution or iOS execution claim',
}
proof.write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps(record, indent=2))
