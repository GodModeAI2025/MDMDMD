#!/usr/bin/env python3
"""Compare the complete Portuguese 1.2.0 tagger rebuild without retaining row sets.

The original reviewed Perl generators run separately in an owned directory;
this verifier binds their unchanged inputs to the pinned archive and preserves
all generated form/lemma/tag fields. It executes only the system sort utility.
No network, archive extraction, app activation or distribution approval.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tarfile
from compare_dictionary_archive import file_digest

MAX_FILE = 2 * 1024**3
MAX_LINE = 4096
MAX_ROWS = 25_000_000
SOURCE_PREFIXES = ('data/src-dict/', 'pos_tagger_scripts/fdic-to-lt/', 'pos_tagger_scripts/libs/')


def stream_digest(stream):
    fingerprint = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        fingerprint.update(chunk)
    return fingerprint.hexdigest()


def checked_row(raw):
    if len(raw) > MAX_LINE or b'\0' in raw or b'\r' in raw:
        raise ValueError('Invalid dictionary row')
    raw.decode('utf-8', errors='strict')
    fields = raw.split(b'\t')
    if len(fields) != 3 or any(not field for field in fields):
        raise ValueError('Expected exactly form, lemma and tag')
    return raw


def generated_rows(stream, nominal):
    for line in stream:
        if len(line) > MAX_LINE:
            raise ValueError('Oversized generated row')
        value = line.removesuffix(b'\n')
        if nominal:
            # Exact ASCII-space-to-tab step from original build-lt.sh.
            value = value.replace(b' ', b'\t')
        else:
            # Exact comment/trailing-whitespace/empty-line cleanup of the
            # original uninflected data. No Unicode normalization or case fold.
            value = re.sub(rb' *#.*$', b'', value).rstrip(b' \t\r\n\v\f')
            if not value:
                continue
        yield checked_row(value)


def bind_source_inputs(archive_path, source_root):
    inputs, seen, expanded = {}, set(), 0
    source_root = source_root.resolve(strict=True)
    with tarfile.open(archive_path) as archive:
        for member in archive:
            relative = member.name.split('/', 1)[-1]
            if not relative.startswith(SOURCE_PREFIXES) or member.isdir():
                continue
            path = Path(relative)
            if not member.isfile() or path.is_absolute() or '..' in path.parts or '\\' in relative or relative in seen:
                raise ValueError('Unsafe or duplicate source input')
            seen.add(relative); expanded += member.size
            if len(seen) > 10_000 or expanded > 100 * 1024**2 or member.size > 20 * 1024**2:
                raise ValueError('Source input bound exceeded')
            local = source_root / relative
            current = source_root
            for component in path.parts:
                current = current / component
                if current.is_symlink():
                    raise ValueError('Original source input symlink')
            if not local.is_file() or local.stat().st_size != member.size:
                raise ValueError('Original source input missing or changed')
            with archive.extractfile(member) as stream:
                expected = stream_digest(stream)
            if file_digest(local) != expected:
                raise ValueError('Original source input differs from pinned archive')
            inputs[relative] = expected
    if not all(name in inputs for name in ['data/src-dict/nouns-fdic.txt', 'data/src-dict/adjectives-fdic.txt',
        'data/src-dict/verbs-fdic.txt', 'pos_tagger_scripts/libs/Flexio.pm',
        'pos_tagger_scripts/fdic-to-lt/inflect-nominals.pl', 'pos_tagger_scripts/fdic-to-lt/conjugate-verbs.pl']):
        raise ValueError('Incomplete morphology inputs')
    return inputs


def sort_rows(source, output, temporary):
    if output.exists() or source.stat().st_size > MAX_FILE:
        raise ValueError('Existing output or oversized row input')
    subprocess.run(['/usr/bin/sort', '-u', '-S', '64M', '-T', str(temporary), '-o', str(output), str(source)],
        env={'LC_ALL': 'C', 'PATH': '/usr/bin:/bin'}, check=True, timeout=300)


def row_fingerprint(path):
    count, fingerprint, previous = 0, hashlib.sha256(), None
    with path.open('rb') as stream:
        for line in stream:
            row = checked_row(line.removesuffix(b'\n'))
            if not line.endswith(b'\n') or previous is not None and previous >= row:
                raise ValueError('Rows are not complete, unique and byte-sorted')
            count += 1
            if count > MAX_ROWS:
                raise ValueError('Row count bound exceeded')
            fingerprint.update(line); previous = row
    return {'rows': count, 'sortedRowsSHA256': fingerprint.hexdigest()}


def verify(archive, source, generated, decoded, output):
    if output.exists():
        raise ValueError('Use a fresh evidence directory')
    inputs = bind_source_inputs(archive, source)
    output.mkdir(parents=True, exist_ok=False)
    temporary = output / 'sort-temp'; temporary.mkdir()
    raw = output / 'generated-rows.tsv'
    generated_hashes = {}
    count = 0
    with raw.open('xb') as destination:
        for name in ['nouns-lt.txt', 'adjectives-lt.txt', 'verbs-lt.txt']:
            path = generated / name
            generated_hashes[name] = file_digest(path)
            with path.open('rb') as stream:
                for row in generated_rows(stream, nominal=True):
                    destination.write(row + b'\n'); count += 1
                    if count > MAX_ROWS or destination.tell() > MAX_FILE:
                        raise ValueError('Generated data bound exceeded')
        for relative in sorted(name for name in inputs if name.startswith('data/src-dict/') and name.endswith('-lt.txt')):
            with (source / relative).open('rb') as stream:
                for row in generated_rows(stream, nominal=False):
                    destination.write(row + b'\n'); count += 1
                    if count > MAX_ROWS or destination.tell() > MAX_FILE:
                        raise ValueError('Generated data bound exceeded')
    expected = output / 'generated-sorted.tsv'; actual = output / 'release-sorted.tsv'
    sort_rows(raw, expected, temporary); sort_rows(decoded, actual, temporary)
    left, right = row_fingerprint(expected), row_fingerprint(actual)
    result = {'sourceArchiveSHA256': file_digest(archive), 'originalInputSHA256': inputs,
        'generatedOutputSHA256': generated_hashes, 'decodedReleaseSHA256': file_digest(decoded),
        'generated': left, 'release': right, 'rowsEqual': left == right,
        'sortMemoryBuffer': '64M',
        'scope': 'Complete original morphology-generator and uninflected-source form/lemma/POS equivalence. No frequency removal, Unicode normalization, synthesis, spelling, byte-identical FSA, licensing or distribution approval.'}
    (output / 'RESULT.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['archive', 'source', 'generated', 'decoded', 'output']:
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--expected-archive-sha256', required=True)
    parser.add_argument('--expected-decoded-sha256', required=True)
    args = parser.parse_args()
    if file_digest(args.archive) != args.expected_archive_sha256 or file_digest(args.decoded) != args.expected_decoded_sha256:
        raise ValueError('Input differs from pinned receipt')
    result = verify(args.archive, args.source, args.generated, args.decoded, args.output)
    print(json.dumps({key:result[key] for key in ['generated','release','rowsEqual']}))
    return 0 if result['rowsEqual'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
