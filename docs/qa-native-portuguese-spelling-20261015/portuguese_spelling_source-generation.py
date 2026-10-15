"""Preserve the original Portuguese speller's input and frequency semantics."""
import io
from pathlib import Path
import re
import tarfile
from compare_dictionary_archive import file_digest, validate_path

VARIANTS = ('pt-BR', 'pt-PT-45', 'pt-PT-90')
PREFIX = 'data/spelling-dict/'
FREQUENCY = re.compile(r'.*<w f="([0-9]+)"(?: flags="(.*?)")?>(.+)</w>.*')


def dictionary_bytes(raw):
    # Original DicChunk: Latin-1 universal newlines, skip count and # comments.
    lines = io.TextIOWrapper(io.BytesIO(raw), encoding='iso-8859-1').readlines()
    if not lines or not lines[0].strip().isdigit():
        raise ValueError('Missing Hunspell count')
    values = [line for line in lines[1:] if not line.startswith('#')]
    if any(len(line) > 4096 for line in values):
        raise ValueError('Oversized dictionary line')
    return (str(len(values)) + '\n' + ''.join(values)).encode('iso-8859-1')


def frequency_bins(path):
    values = {}
    with path.open(encoding='utf-8') as stream:
        for line in stream:
            if len(line) > 4096:
                raise ValueError('Oversized frequency line')
            match = FREQUENCY.fullmatch(line.rstrip('\r\n'))
            if match:
                value = int(match[1])
                # Both actual original lists max at 221. Reject other mapping modes.
                if value > 255:
                    raise ValueError('Logarithmic frequency mapping outside this proof')
                values[match[3]] = value
    if not values:
        raise ValueError('Empty frequency list')
    return {word: value * 26 // 256 for word, value in values.items()}


def write_frequency_rows(words, frequencies, output):
    with words.open('rb') as source, output.open('xb') as target:
        for index, raw in enumerate(source, 1):
            if index > 25_000_000 or len(raw) > 4096 or not raw.endswith(b'\n'):
                raise ValueError('Invalid spelling word record')
            word = raw[:-1].decode('utf-8', errors='strict')
            if not word or word.startswith('\t') or any(char in word for char in '\0\r'):
                raise ValueError('Invalid spelling word')
            # Original DictionaryBuilder keys the first field but retains the full line.
            key = word.split('\t', 1)[0]
            target.write(raw[:-1] + b'\t' + str(frequencies.get(key, 0)).encode('ascii') + b'\n')


def bind_spelling_inputs(archive_path, source_root):
    root = source_root.resolve(strict=True)
    result, seen, total = {}, set(), 0
    with tarfile.open(archive_path) as archive:
        for member in archive:
            validate_path(member.name, seen)
            total += member.size
            if len(seen) > 200_000 or total > 2 * 1024**3 or member.size > 100 * 1024**2:
                raise ValueError('Source archive bound exceeded')
            relative = member.name.split('/', 1)[-1]
            if not relative.startswith(PREFIX) or member.isdir():
                continue
            if not member.isfile():
                raise ValueError('Source link refused')
            if relative in result:
                raise ValueError('Duplicate source input')
            current = root
            for component in Path(relative).parts:
                current = current / component
                if current.is_symlink():
                    raise ValueError('Local source link refused')
            raw = archive.extractfile(member).read()
            if len(raw) != member.size or current.read_bytes() != raw:
                raise ValueError('Changed source input')
            result[relative] = file_digest(current)
    required = {PREFIX + 'hunspell/' + v.replace('-', '_') + suffix for v in VARIANTS for suffix in ('.dic', '.aff')}
    required |= {PREFIX + 'hunspell/compounds/' + v.replace('-', '_') + '.dic' for v in VARIANTS}
    required |= {PREFIX + v + '.info' for v in VARIANTS}
    required |= {PREFIX + 'pt_BR_wordlist.xml', PREFIX + 'pt_PT_wordlist.xml'}
    if not required <= result.keys():
        raise ValueError('Incomplete Portuguese spelling source')
    return result
