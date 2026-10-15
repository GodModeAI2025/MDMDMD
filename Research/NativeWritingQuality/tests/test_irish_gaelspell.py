import hashlib
import io
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verify_irish_gaelspell import (LIMITATIONS, archive_members, compare_resource,
                                   dictionary_summary, pinned_file, verify)


class IrishGaelspellTests(unittest.TestCase):
    def test_exact_dictionary_includes_count_encoding_and_all_rows(self):
        raw = "3\nab/H\nábhair/U\nab/H\n".encode()
        result = compare_resource("ga_IE.dic", raw, raw)
        self.assertTrue(result["byteIdentical"])
        self.assertTrue(result["allRowsEqual"])
        self.assertEqual(result["generated"]["rows"], 3)

    def test_changed_duplicate_row_is_not_hidden_by_set_comparison(self):
        expected = b"3\na/H\na/H\nb/U\n"
        changed = b"3\na/H\nb/U\nb/U\n"
        result = compare_resource("ga_IE.dic", changed, expected)
        self.assertFalse(result["byteIdentical"])
        self.assertFalse(result["allRowsEqual"])

    def test_semantically_equal_reordering_and_newlines_are_not_byte_proof(self):
        for changed in [b"2\nb/U\na/H\n", b"2\r\na/H\r\nb/U\r\n"]:
            with self.subTest(changed=changed):
                result = compare_resource("ga_IE.dic", changed, b"2\na/H\nb/U\n")
                self.assertFalse(result["byteIdentical"])
                self.assertTrue(result["allRowsEqual"])

    def test_wrong_header_and_encoding_fail(self):
        for invalid in [b"3\na\nb\n", b"two\na\nb\n", b"1\n\xff\n", b""]:
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                dictionary_summary(invalid)

    def test_hash_mismatch_and_symlink_fail_without_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); original = root / "original"; original.write_bytes(b"source")
            expected = hashlib.sha256(b"source").hexdigest()
            self.assertEqual(pinned_file(original, expected)["sha256"], expected)
            alias = root / "alias"; alias.symlink_to(original)
            with self.assertRaises(ValueError): pinned_file(alias, expected)
            original.write_bytes(b"changed")
            with self.assertRaises(ValueError): pinned_file(original, expected)
            with self.assertRaises(ValueError): verify(original, original, original, root / "result")
            self.assertFalse((root / "result").exists())

    def test_existing_output_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); marker = root / "evidence"; marker.write_bytes(b"keep")
            with self.assertRaises(ValueError): verify(root / "none", root / "none", root / "none", root)
            self.assertEqual(marker.read_bytes(), b"keep")

    def test_tar_traversal_symlink_alias_and_file_parent_collision_fail(self):
        cases = [[("../escape", b"x", None)], [("root/link", b"", "target")],
                 [("root/README", b"a", None), ("root/readme", b"b", None)],
                 [("root/a", b"a", None), ("root/a/b", b"b", None)],
                 [("root/a", b"a", None), ("other/b", b"b", None)]]
        for entries in cases:
            with self.subTest(entries=entries), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "archive.tar.gz"
                with tarfile.open(path, "w:gz") as target:
                    for name, raw, link in entries:
                        item = tarfile.TarInfo(name); item.size = len(raw)
                        if link:
                            item.type = tarfile.SYMTYPE; item.linkname = link
                        target.addfile(item, io.BytesIO(raw))
                with self.assertRaises(ValueError): archive_members(path)

    def test_notices_and_other_irish_resource_limits_remain_explicit(self):
        text = "\n".join(LIMITATIONS)
        for required in ["GPLv2", "FST", "Dictionary/IG", "Gin", "Roman", "distribution approval"]:
            self.assertIn(required, text)


if __name__ == "__main__":
    unittest.main()
