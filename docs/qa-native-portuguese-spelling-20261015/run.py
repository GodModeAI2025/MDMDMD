from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import time
import zipfile

repo = Path('/Users/markzimmermann/Documents/Codex/2026-10-08/mach/outputs/Skriptum')
work = Path(__file__).resolve().parent
base = work.parent
sys.path.insert(0, str(repo / 'Research/NativeWritingQuality'))
from portuguese_spelling_source import bind_spelling_inputs, dictionary_bytes, frequency_bins, write_frequency_rows, VARIANTS
from verify_ukrainian_generated import compare_sorted
from compare_dictionary_archive import file_digest as sha

archive = base / 'native-quality-portuguese-20261015/Portuguese-1.2.0.tar.gz'
assert sha(archive) == 'dd771c85ed0b8bd439d73477021225c621fa07730824b32a6f4bca969124f898'
source_inputs = bind_spelling_inputs(archive, work / 'source')
aot = base / 'native-quality-aot-20261014'
java = aot / 'graalvm-svm-java17-darwin-m1-gluon-22.1.0.1-Final/Contents/Home/bin/java'
jar = aot / 'm2/org/languagetool/portuguese-pos-dict/1.2.0/portuguese-pos-dict-1.2.0.jar'
assert sha(jar) == 'fe8da88bb31b6372855741fbd81ee1c7477b4f8a0624d3dafd20ee23e184650e'
cp = (work / 'CLASSPATH.txt').read_text().strip()
files = [archive, jar, java, work / 'unmunch', work / 'WordTokenizer.java', work / 'DictionaryBuilder.java',
         work / 'dictionary-tools-5c661e7.tar.gz', work / 'hunspell-2969be9.tar.gz', Path(__file__),
         repo / 'Research/NativeWritingQuality/portuguese_spelling_source.py',
         repo / 'Research/NativeWritingQuality/UkrainianSpellingRows.java',
         repo / 'Research/NativeWritingQuality/PortugueseSpellingRows.java',
         repo / 'docs/qa-native-portuguese-source-20261015/ROW_EQUIVALENCE.json',
         *map(Path, cp.split(os.pathsep)), *(work / 'classes').rglob('*.class')]
before = {str(p): sha(p) for p in files if p.is_file()}
output = work / 'reconstruction-final'
output.mkdir(exist_ok=False)
(output / 'INPUTS.json').write_text(json.dumps({'files': before, 'sourceInputs': source_inputs}, indent=2) + '\n')
steps = []
deny_network = ['/usr/bin/sandbox-exec', '-p', '(version 1) (allow default) (deny network*)']
java_prefix = deny_network + [str(java), '-Xmx768m', '-Dfile.encoding=UTF-8', '-cp', str(work / 'classes') + os.pathsep + cp]

def run(name, command, stdin=None, stdout=None):
    print('Running ' + name, flush=True)
    start = time.monotonic()
    stdout = stdout or output / (name + '.stdout')
    with stdout.open('xb') as out, (output / (name + '.stderr')).open('xb') as err:
        with (stdin.open('rb') if stdin else open(os.devnull, 'rb')) as incoming:
            result = subprocess.run(list(map(str, command)), stdin=incoming, stdout=out, stderr=err,
                                    cwd=output, env=dict(os.environ, LC_ALL='C'), timeout=1200)
    steps.append({'name': name, 'argv': list(map(str, command)), 'stdin': str(stdin) if stdin else None,
                  'stdout': str(stdout), 'exitCode': result.returncode, 'seconds': time.monotonic() - start,
                  'stdoutSHA256': sha(stdout), 'stderrSHA256': sha(output / (name + '.stderr'))})
    (output / 'STEPS.json').write_text(json.dumps(steps, indent=2) + '\n')
    if result.returncode: raise RuntimeError(name + ' failed; original stderr retained')

summary = {}
for variant in VARIANTS:
    out = output / variant; out.mkdir()
    run(variant + '-decode', java_prefix + ['PortugueseSpellingRows', jar, variant, out / 'binary-words.txt', out / 'binary-frequencies.tsv'])
    underscored = variant.replace('-', '_')
    root = work / 'source/data/spelling-dict'
    aff = root / 'hunspell' / (underscored + '.aff')
    for kind, original in [('main', root / 'hunspell' / (underscored + '.dic')),
                           ('compounds', root / 'hunspell/compounds' / (underscored + '.dic'))]:
        cleaned = out / (kind + '.dic'); cleaned.write_bytes(dictionary_bytes(original.read_bytes()))
        latin = out / (kind + '-unmunched-latin1.txt')
        run(variant + '-unmunch-' + kind, deny_network + [work / 'unmunch', cleaned, aff], stdout=latin)
        utf8 = out / (kind + '-unmunched-utf8.txt')
        with latin.open('r', encoding='iso-8859-1') as src, utf8.open('x', encoding='utf-8') as dest:
            for line in src: dest.write(line)
    tokenized = out / 'tokenized.txt'
    run(variant + '-tokenize', java_prefix + ['org.languagetool.dev.archive.WordTokenizer', 'pt'],
        stdin=out / 'main-unmunched-utf8.txt', stdout=tokenized)
    merged = out / 'source-merged.txt'
    with merged.open('xb') as dest:
        for path in [tokenized, out / 'compounds-unmunched-utf8.txt']:
            with path.open('rb') as src:
                for line in src:
                    if line != b'\n' and not line.startswith(b'\t'): dest.write(line)
    run(variant + '-sort-source', ['/usr/bin/sort', '-u', '-S', '64M', '-T', out, '-o', out / 'source-sorted.txt', merged])
    run(variant + '-sort-binary', ['/usr/bin/sort', '-u', '-S', '64M', '-T', out, '-o', out / 'binary-sorted.txt', out / 'binary-words.txt'])
    freq_path = root / ('pt_BR_wordlist.xml' if variant == 'pt-BR' else 'pt_PT_wordlist.xml')
    bins = frequency_bins(freq_path)
    write_frequency_rows(out / 'source-sorted.txt', bins, out / 'source-frequencies.tsv')
    run(variant + '-sort-source-frequencies', ['/usr/bin/sort', '-u', '-S', '64M', '-T', out, '-o', out / 'source-frequencies-sorted.tsv', out / 'source-frequencies.tsv'])
    run(variant + '-sort-binary-frequencies', ['/usr/bin/sort', '-u', '-S', '64M', '-T', out, '-o', out / 'binary-frequencies-sorted.tsv', out / 'binary-frequencies.tsv'])
    with zipfile.ZipFile(jar) as binary:
        info_equal = binary.read('org/languagetool/resource/pt/spelling/' + variant + '.info') == (root / (variant + '.info')).read_bytes()
    summary[variant] = {'words': compare_sorted(out / 'source-sorted.txt', out / 'binary-sorted.txt'),
                        'frequencies': compare_sorted(out / 'source-frequencies-sorted.tsv', out / 'binary-frequencies-sorted.tsv'),
                        'sourceFrequencyWords': len(bins), 'infoBytesEqual': info_equal,
                        'sourceWordsSHA256': sha(out / 'source-sorted.txt'), 'binaryWordsSHA256': sha(out / 'binary-sorted.txt'),
                        'sourceFrequenciesSHA256': sha(out / 'source-frequencies-sorted.tsv'),
                        'binaryFrequenciesSHA256': sha(out / 'binary-frequencies-sorted.tsv')}
    (output / 'COMPARISON.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({variant: summary[variant]}, ensure_ascii=False), flush=True)
assert before == {str(p): sha(Path(p)) for p in before}
assert source_inputs == bind_spelling_inputs(archive, work / 'source')
print('All generator, binary and source inputs unchanged; all three comparisons recorded', flush=True)
