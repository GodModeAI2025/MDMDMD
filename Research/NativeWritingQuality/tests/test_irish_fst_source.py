import io
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import verify_irish_fst_source as verifier


class IrishFSTSourceTests(unittest.TestCase):
    def test_preserves_accents_case_and_tag_order(self):
        kind, row = verifier.convert_pair("Éire+Noun+Prop+Gen\tÉireann\n".encode())
        self.assertEqual((kind, row), ("row", "Éireann\tÉire\tNoun:Prop:Gen\n".encode()))

    def test_only_documented_epsilon_warning_is_accepted(self):
        self.assertEqual(verifier.convert_pair(b"\t\n"), ("epsilon", b"Error in line: \t\n"))
        for malformed in (b"lemma\tform\n", b"+Noun\tform\n", b"lemma+Noun\t\n",
                          b"lemma+Noun\tform", b"lemma+Noun\tform\textra\n",
                          b"lemma+Noun\tform\r\n", b"lemma+Noun\t\xff\n"):
            with self.subTest(malformed=malformed), self.assertRaises(ValueError):
                verifier.convert_pair(malformed)

    def test_original_exclusions_are_not_dictionary_rows(self):
        self.assertEqual(verifier.convert_pair(b"++Num+Op\t+\n"), ("plus", b""))
        self.assertEqual(verifier.convert_pair(b"<body>+XMLTag\t<body>\n"),
                         ("filtered", b"<body>\t<body>\tXMLTag\n"))
        self.assertEqual(verifier.convert_pair(b"x+Noun+Event\tx\n")[0], "row")

    def test_exact_perl_output_is_required_and_warning_is_recorded(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "pairs").write_bytes(b"\t\nx+Noun\tx\n++Num+Op\t+\n")
            (root / "perl").write_bytes(b"Error in line: \t\nx\tx\tNoun\n")
            counts, tags, excluded, _, _ = verifier.convert_pairs(root / "pairs", root / "perl", root / "rows")
            self.assertEqual(counts, {"pairs": 3, "row": 1, "epsilon": 1, "filtered": 0, "plus": 1})
            self.assertEqual(tags, {b"Noun"}); self.assertEqual(excluded, set())
            self.assertEqual((root / "rows").read_bytes(), b"x\tx\tNoun\n")
            (root / "perl").write_bytes(b"x\tx\tNoun\n")
            with self.assertRaisesRegex(ValueError, "Perl output differs"):
                verifier.convert_pairs(root / "pairs", root / "perl", root / "changed")

    def test_original_tree_rejects_changed_file_and_symlink(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); source = root / "source"; source.mkdir()
            (source / "lexicon").write_bytes(b"original")
            files = {"lexicon": (b"original", 0o644)}
            self.assertIn("lexicon", verifier.bind_original_tree(files, source))
            (source / "lexicon").write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                verifier.bind_original_tree(files, source)
            (source / "lexicon").unlink(); (root / "other").write_bytes(b"original")
            (source / "lexicon").symlink_to(root / "other")
            with self.assertRaisesRegex(ValueError, "symlink"):
                verifier.bind_original_tree(files, source)

    def inventory_archive(self, mutate=None, filter_row=b"x\tx\tXMLTag\n"):
        data = io.BytesIO()
        entries = {name: b"Noun\nVerb\n" for name in verifier.TAGS}
        if mutate:
            mutate(entries)
        with zipfile.ZipFile(data, "w") as archive:
            for name, value in entries.items():
                archive.writestr(verifier.RESOURCE_ROOT + name, value)
            archive.writestr(verifier.RESOURCE_ROOT + "filter-archaic.txt", filter_row)
        data.seek(0)
        return zipfile.ZipFile(data)

    def test_all_five_inventories_and_filter_scope_are_retained(self):
        with self.inventory_archive() as archive:
            inventories, result = verifier.compare_inventories(archive, {b"Noun", b"Verb"},
                {b"x\tx\tXMLTag\n", b"y\ty\tXMLTag\n"})
        self.assertEqual(len(inventories), 5)
        self.assertFalse(result["exactHistoricalSelectionReconstructed"])
        self.assertEqual(result["additionalGeneratorExclusions"], ["y\ty\tXMLTag"])

    def test_changed_missing_and_extra_inventory_fail(self):
        mutations = [lambda entries: entries.update({verifier.TAGS[0]: b"Noun\n"}),
                     lambda entries: entries.pop(verifier.TAGS[0]),
                     lambda entries: entries.update({"extra_tags.txt": b"Noun\nVerb\n"})]
        for mutate in mutations:
            with self.subTest(mutation=mutate), self.inventory_archive(mutate) as archive, self.assertRaises(ValueError):
                verifier.compare_inventories(archive, {b"Noun", b"Verb"}, {b"x\tx\tXMLTag\n"})

    def test_filter_cannot_hide_unaccounted_for_entries(self):
        with self.inventory_archive(filter_row=b"y\ty\tNoun\n") as archive, self.assertRaisesRegex(ValueError, "absent"):
            verifier.compare_inventories(archive, {b"Noun", b"Verb"}, {b"x\tx\tXMLTag\n"})

    def test_existing_row_output_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ("pairs", "perl", "rows"):
                (root / name).write_bytes(b"witness")
            with self.assertRaises(FileExistsError):
                verifier.convert_pairs(root / "pairs", root / "perl", root / "rows")
            self.assertEqual((root / "rows").read_bytes(), b"witness")


if __name__ == "__main__":
    unittest.main()
