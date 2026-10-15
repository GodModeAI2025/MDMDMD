from pathlib import Path
import json
import os
import subprocess
import sys
import time
import zipfile

repo = Path('/Users/markzimmermann/Documents/Codex/2026-10-08/mach/outputs/Skriptum')
sys.path.insert(0, str(repo / 'Research/NativeWritingQuality'))
from portuguese_spelling_source import write_fsa_records, VARIANTS
from compare_dictionary_archive import file_digest as sha

work = Path(__file__).resolve().parent
original = work / 'reconstruction-final'
comparison = json.loads((original / 'COMPARISON.json').read_text())
java = work.parent / 'native-quality-aot-20261014/graalvm-svm-java17-darwin-m1-gluon-22.1.0.1-Final/Contents/Home/bin/java'
jar = work.parent / 'native-quality-aot-20261014/m2/org/languagetool/portuguese-pos-dict/1.2.0/portuguese-pos-dict-1.2.0.jar'
assert sha(jar) == 'fe8da88bb31b6372855741fbd81ee1c7477b4f8a0624d3dafd20ee23e184650e'
cp = str(work / 'classes') + os.pathsep + (work / 'CLASSPATH.txt').read_text().strip()
files = [Path(__file__), repo / 'Research/NativeWritingQuality/RebuildSpellingFSA.java',
         repo / 'Research/NativeWritingQuality/portuguese_spelling_source.py',
         work / 'morfologik-tools-2.1.9-sources.jar', work / 'DictionaryBuilder.java',
         work / 'SpellDictionaryBuilder.java', *map(Path, cp.split(os.pathsep)), *(work / 'classes').rglob('*.class')]
before = {str(p): sha(p) for p in files if p.is_file()}
out = work / 'fsa-rebuild'; out.mkdir(exist_ok=False)
(out / 'INPUTS.json').write_text(json.dumps(before, indent=2) + '\n')
steps, result = [], {}
for variant in VARIANTS:
    source = original / variant / 'source-frequencies-sorted.tsv'
    assert sha(source) == comparison[variant]['sourceFrequenciesSHA256']
    records, sorted_records, binary = [out / (variant + suffix) for suffix in ['-records.txt', '-sorted.txt', '.dict']]
    write_fsa_records(source, records)
    commands = [[str(x) for x in ['/usr/bin/sort', '-u', '-S', '64M', '-T', out, '-o', sorted_records, records]],
                ['/usr/bin/sandbox-exec', '-p', '(version 1) (allow default) (deny network*)', str(java), '-ea', '-Xmx768m',
                 '-cp', cp, 'RebuildSpellingFSA', str(sorted_records), str(binary)]]
    for index, command in enumerate(commands):
        print(variant + (' sort encoded records' if index == 0 else ' serialize CFSA2'), flush=True)
        start = time.monotonic()
        with (out / (variant + '-' + str(index) + '.stdout')).open('xb') as stdout, (out / (variant + '-' + str(index) + '.stderr')).open('xb') as stderr:
            p = subprocess.run(command, stdout=stdout, stderr=stderr, cwd=out, env=dict(os.environ, LC_ALL='C'), timeout=600)
        steps.append({'variant': variant, 'argv': command, 'exitCode': p.returncode, 'seconds': time.monotonic() - start})
        (out / 'STEPS.json').write_text(json.dumps(steps, indent=2) + '\n')
        if p.returncode: raise RuntimeError('FSA build failed; original logs retained')
    with zipfile.ZipFile(jar) as archive:
        resource = 'org/languagetool/resource/pt/spelling/' + variant + '.dict'
        actual = archive.read(resource)
        import hashlib
        expected_sha = hashlib.sha256(actual).hexdigest()
        equal = binary.read_bytes() == actual
    result[variant] = {'resource': resource, 'sourceFrequencyRowsSHA256': sha(source), 'encodedSortedRowsSHA256': sha(sorted_records),
                       'rebuiltSHA256': sha(binary), 'originalSHA256': expected_sha, 'bytes': binary.stat().st_size,
                       'byteIdentical': equal, 'wordFrequencyRows': comparison[variant]['frequencies']['commonRows']}
    (out / 'REBUILD.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({variant: result[variant]}), flush=True)
assert before == {str(p): sha(Path(p)) for p in before}
print('All serializer and source inputs unchanged', flush=True)
