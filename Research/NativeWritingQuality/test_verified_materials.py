import copy
import hashlib
from pathlib import Path
import tempfile
import unittest
import zipfile

from bundle_verified_materials import build


class VerifiedMaterialsTests(unittest.TestCase):
    def fixture(self, root):
        source = root / "inputs"; source.mkdir()
        file = source / "original.txt"; file.write_bytes(b"Original\r\n\xff\x00")
        spec = {"unresolved": ["Source review remains open"], "requiredPaths": ["upstream/original.txt"], "files": [
            {"source": str(file), "path": "upstream/original.txt",
             "sha256": hashlib.sha256(file.read_bytes()).hexdigest()}]}
        return source, file, spec

    def test_deterministic_archive_preserves_original_binary_text_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source, file, spec = self.fixture(root)
            first = build(spec, [source], root / "first")
            second = build(spec, [source], root / "second")
            self.assertEqual(first["sha256"], second["sha256"])
            self.assertTrue(first["integrityVerified"])
            self.assertEqual(first["unresolved"], spec["unresolved"])
            with zipfile.ZipFile(root / "first/SourceMaterials.zip") as archive:
                self.assertEqual(archive.read("upstream/original.txt"), file.read_bytes())

    def test_changed_source_is_rejected_before_output_creation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source, file, spec = self.fixture(root)
            file.write_bytes(b"changed")
            with self.assertRaises(ValueError): build(spec, [source], root / "output")
            self.assertFalse((root / "output").exists())

    def test_existing_evidence_directory_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source, _, spec = self.fixture(root)
            output = root / "existing"; output.mkdir(); (output / "witness").write_bytes(b"keep")
            with self.assertRaises(ValueError): build(spec, [source], output)
            self.assertEqual((output / "witness").read_bytes(), b"keep")

    def test_input_outside_the_explicit_roots_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); _, _, spec = self.fixture(root)
            allowed = root / "allowed"; allowed.mkdir()
            with self.assertRaises(ValueError): build(spec, [allowed], root / "output")

    def test_symlink_cannot_select_a_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source, file, spec = self.fixture(root)
            link = source / "alias"; link.symlink_to(file)
            spec["files"][0]["source"] = str(link)
            with self.assertRaises(ValueError): build(spec, [source], root / "output")

    def test_escaping_and_reserved_manifest_paths_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source, _, spec = self.fixture(root)
            for path in ["../outside", "/absolute", "folder/../outside", "folder\\outside", "MANIFEST.json"]:
                changed = copy.deepcopy(spec); changed["files"][0]["path"] = path
                with self.assertRaises(ValueError): build(changed, [source], root / "output")

    def test_case_aliases_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source, _, spec = self.fixture(root)
            alias = copy.deepcopy(spec["files"][0]); alias["path"] = "UPSTREAM/ORIGINAL.TXT"
            spec["files"].append(alias)
            with self.assertRaises(ValueError): build(spec, [source], root / "output")

    def test_declared_required_notice_cannot_be_silently_omitted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source, _, spec = self.fixture(root)
            spec["requiredPaths"].append("upstream/README.md")
            with self.assertRaises(ValueError): build(spec, [source], root / "output")
            self.assertFalse((root / "output").exists())


if __name__ == "__main__":
    unittest.main()
