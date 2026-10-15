import io
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from portuguese_spelling_source import dictionary_bytes, frequency_bins, write_frequency_rows, write_fsa_records, bind_spelling_inputs, PREFIX, VARIANTS


class PortugueseSpellingSourceTests(unittest.TestCase):
    def test_latin1_count_comments_and_original_whitespace(self):
        self.assertEqual(dictionary_bytes('3\r\n# remark\r\nação/A\r\n # literal\r\n'.encode('latin1')),
                         '2\nação/A\n # literal\n'.encode('latin1'))
        with self.assertRaises(ValueError): dictionary_bytes(b'word\n')
        with self.assertRaises(ValueError): dictionary_bytes(b'1\n' + b'x' * 4097)

    def test_original_frequency_overwrite_flags_and_literal_entities(self):
        with tempfile.TemporaryDirectory() as folder:
            p = Path(folder) / 'freq.xml'
            p.write_text('<w f="255">ação</w>\n<w f="128" flags="x">ação</w>\n<w f="0">a&amp;b</w>\n', encoding='utf-8')
            self.assertEqual(frequency_bins(p), {'ação': 13, 'a&amp;b': 0})
            p.write_text('<w f="256">x</w>\n')
            with self.assertRaises(ValueError): frequency_bins(p)
            p.write_text('<words/>\n')
            with self.assertRaises(ValueError): frequency_bins(p)

    def test_unicode_exact_rows_and_no_output_overwrite(self):
        with tempfile.TemporaryDirectory() as folder:
            words, out = Path(folder) / 'words', Path(folder) / 'out'
            words.write_bytes('Café\nCafé\n🦊\n'.encode())
            write_frequency_rows(words, {'Café': 25}, out)
            self.assertEqual(out.read_bytes(), 'Café\t25\nCafé\t0\n🦊\t0\n'.encode())
            with self.assertRaises(FileExistsError): write_frequency_rows(words, {}, out)

    def test_invalid_word_records_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            for index, bad in enumerate([b'bad\rword\n', b'bad\0word\n', b'\xff\n', b'no-final-newline', b'\n']):
                p = Path(folder) / ('words' + str(index)); p.write_bytes(bad)
                with self.assertRaises((ValueError, UnicodeError)): write_frequency_rows(p, {}, p.with_suffix('.out'))

    def test_original_tabs_retained_but_frequency_lookup_uses_first_field(self):
        with tempfile.TemporaryDirectory() as folder:
            words, out = Path(folder) / 'words', Path(folder) / 'out'
            words.write_bytes('pré-antessoubé-la\t\t\n'.encode())
            write_frequency_rows(words, {'pré-antessoubé-la': 13}, out)
            self.assertEqual(out.read_bytes(), 'pré-antessoubé-la\t\t\t13\n'.encode())

    def test_fsa_record_encoding_preserves_tabs_and_refuses_invalid_bins(self):
        with tempfile.TemporaryDirectory() as folder:
            source, out = Path(folder) / 'rows', Path(folder) / 'records'
            source.write_bytes('pré-antessoubé-la\t\t\t13\n🦊\t25\n'.encode())
            write_fsa_records(source, out)
            self.assertEqual(out.read_bytes(), 'pré-antessoubé-la\t\t_N\n🦊_Z\n'.encode())
            with self.assertRaises(FileExistsError): write_fsa_records(source, out)
            for index, line in enumerate([b'word\t26\n', b'word\t-1\n', b'word\tA\n', b'word\t0', b'\t0\n', b'wo\0rd\t0\n']):
                source.write_bytes(line)
                with self.assertRaises(ValueError): write_fsa_records(source, out.with_suffix('.' + str(index)))

    def test_all_required_sources_bound_and_mutation_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            root, archive = Path(folder) / 'source', Path(folder) / 'source.tar'
            names = [PREFIX + 'hunspell/' + v.replace('-', '_') + ext for v in VARIANTS for ext in ('.dic', '.aff')]
            names += [PREFIX + 'hunspell/compounds/' + v.replace('-', '_') + '.dic' for v in VARIANTS]
            names += [PREFIX + v + '.info' for v in VARIANTS]
            names += [PREFIX + 'pt_BR_wordlist.xml', PREFIX + 'pt_PT_wordlist.xml']
            with tarfile.open(archive, 'w') as tar:
                for name in names:
                    p = root / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(b'original\r\n')
                    info = tarfile.TarInfo('release/' + name); info.size = 10; tar.addfile(info, io.BytesIO(b'original\r\n'))
            self.assertEqual(len(bind_spelling_inputs(archive, root)), 14)
            victim = root / names[0]; victim.write_bytes(b'changed')
            with self.assertRaises(ValueError): bind_spelling_inputs(archive, root)
            victim.unlink(); victim.symlink_to(root / names[1])
            with self.assertRaises(ValueError): bind_spelling_inputs(archive, root)

    def test_traversing_and_incomplete_archive_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            root, archive = Path(folder), Path(folder) / 'source.tar'
            with tarfile.open(archive, 'w') as tar:
                info = tarfile.TarInfo('release/../escape'); info.size = 1; tar.addfile(info, io.BytesIO(b'x'))
            with self.assertRaises(ValueError): bind_spelling_inputs(archive, root)

    def test_different_archive_roots_cannot_alias_one_input(self):
        with tempfile.TemporaryDirectory() as folder:
            root, archive = Path(folder), Path(folder) / 'source.tar'
            name = PREFIX + 'example'; p = root / name
            p.parent.mkdir(parents=True); p.write_bytes(b'x')
            with tarfile.open(archive, 'w') as tar:
                for prefix in ['first/', 'second/']:
                    info = tarfile.TarInfo(prefix + name); info.size = 1; tar.addfile(info, io.BytesIO(b'x'))
            with self.assertRaisesRegex(ValueError, 'Duplicate source'): bind_spelling_inputs(archive, root)
            with tarfile.open(archive, 'w'): pass
            with self.assertRaises(ValueError): bind_spelling_inputs(archive, root)


if __name__ == '__main__': unittest.main()
