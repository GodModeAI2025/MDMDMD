import io
from pathlib import Path
import tempfile
import tarfile
import unittest
from verify_portuguese_source import bind_source_inputs, checked_row, generated_rows, row_fingerprint, stream_digest


class PortugueseSourceTests(unittest.TestCase):
    def test_stream_hash_is_compatible_with_the_system_python(self):
        import hashlib
        raw = 'e\u0301 🦊'.encode()*300000
        self.assertEqual(stream_digest(io.BytesIO(raw)), hashlib.sha256(raw).hexdigest())

    def test_original_input_binding_rejects_changes_and_interior_links(self):
        names = ['data/src-dict/nouns-fdic.txt', 'data/src-dict/adjectives-fdic.txt',
            'data/src-dict/verbs-fdic.txt', 'pos_tagger_scripts/libs/Flexio.pm',
            'pos_tagger_scripts/fdic-to-lt/inflect-nominals.pl', 'pos_tagger_scripts/fdic-to-lt/conjugate-verbs.pl']
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source = root/'source'; source.mkdir()
            archive = root/'source.tar'
            with tarfile.open(archive, 'w') as out:
                for name in names:
                    path = source/name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(b'original')
                    info = tarfile.TarInfo('release/'+name); info.size = 8; out.addfile(info, io.BytesIO(b'original'))
            self.assertEqual(len(bind_source_inputs(archive, source)), 6)
            path = source/names[0]; path.write_bytes(b'changed!')
            with self.assertRaises(ValueError):bind_source_inputs(archive, source)
            path.write_bytes(b'original')
            (source/'data').rename(root/'linked-data')
            (source/'data').symlink_to(root/'linked-data', target_is_directory=True)
            with self.assertRaises(ValueError):bind_source_inputs(archive, source)

    def test_original_ascii_conversion_preserves_unicode_and_tags(self):
        row = 'café cafe\u0301 NCMS000'.encode()
        self.assertEqual(list(generated_rows(io.BytesIO(row+b'\n'), nominal=True)),
            ['café\tcafe\u0301\tNCMS000'.encode()])

    def test_only_uninflected_comments_and_blank_lines_are_cleaned(self):
        data = b'# comment\n\nform\tlemma\tTAG  # source\n'
        self.assertEqual(list(generated_rows(io.BytesIO(data), nominal=False)), [b'form\tlemma\tTAG'])

    def test_malformed_and_oversized_rows_are_refused(self):
        for value in [b'form\tlemma', b'form\t\tTAG', b'form\tlemma\tTAG\textra',
            b'form\tlemma\tTA\0G', b'form\tlemma\tTAG\r', b'\xff\tlemma\tTAG', b'a'*5000]:
            with self.assertRaises((ValueError, UnicodeError)):checked_row(value)

    def test_sorted_fingerprint_is_exact_and_duplicate_sensitive(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root)/'rows.tsv'
            path.write_bytes(b'a\ta\tA\nb\tb\tB\n')
            self.assertEqual(row_fingerprint(path)['rows'],2)
            for raw in [b'a\ta\tA\na\ta\tA\n',b'b\tb\tB\na\ta\tA\n',b'a\ta\tA']:
                path.write_bytes(raw)
                with self.assertRaises(ValueError):row_fingerprint(path)


if __name__ == '__main__':unittest.main()
