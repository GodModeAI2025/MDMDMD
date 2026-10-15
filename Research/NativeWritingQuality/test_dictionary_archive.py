import io
from pathlib import Path
import tarfile
import tempfile
import unittest
import zipfile

from compare_dictionary_archive import compare


class DictionaryArchiveTests(unittest.TestCase):
    def inputs(self, root, entries, jar_entries=None):
        jar = root / "pinned.jar"
        with zipfile.ZipFile(jar, "w") as archive:
            for name, data in jar_entries or [("org/languagetool/resource/xx/data.txt", b"source\r\n")]:
                archive.writestr(name, data)
        source = root / "source.tar.gz"
        with tarfile.open(source, "w:gz") as archive:
            for name, data in entries:
                info = tarfile.TarInfo(name); info.size = len(data)
                archive.addfile(info, io.BytesIO(data))
        return jar, source

    def test_exact_bytes_survive_without_newline_normalization(self):
        with tempfile.TemporaryDirectory() as directory:
            args = self.inputs(Path(directory), [("pinned/src/org/languagetool/resource/xx/data.txt", b"source\r\n")])
            result = compare(*args)
            self.assertTrue(result["allResourcesByteIdentical"])
            self.assertEqual(result["resourceCount"], 1)
            self.assertEqual(result["matched"][0]["bytes"], 8)

    def test_same_name_with_changed_bytes_remains_a_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            args = self.inputs(Path(directory), [("pinned/src/org/languagetool/resource/xx/data.txt", b"source\n")])
            result = compare(*args)
            self.assertFalse(result["allResourcesByteIdentical"])
            self.assertEqual(len(result["differentSamePath"]), 1)

    def test_same_basename_under_another_resource_path_is_not_a_match(self):
        with tempfile.TemporaryDirectory() as directory:
            args = self.inputs(Path(directory), [("pinned/src/org/languagetool/resource/yy/data.txt", b"source\r\n")])
            result = compare(*args)
            self.assertEqual(len(result["missingSamePath"]), 1)
            self.assertEqual(result["matched"], [])

    def test_duplicate_source_member_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            value = ("pinned/src/org/languagetool/resource/xx/data.txt", b"source\r\n")
            args = self.inputs(Path(directory), [value, value])
            with self.assertRaises(ValueError): compare(*args)

    def test_escaping_archive_path_is_rejected_without_extraction(self):
        with tempfile.TemporaryDirectory() as directory:
            args = self.inputs(Path(directory), [("../escaped.txt", b"no")])
            with self.assertRaises(ValueError): compare(*args)

    def test_compiled_class_cannot_be_presented_as_a_data_only_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            args = self.inputs(Path(directory), [], [("Implementation.class", b"class")])
            with self.assertRaises(ValueError): compare(*args)


if __name__ == "__main__":
    unittest.main()
