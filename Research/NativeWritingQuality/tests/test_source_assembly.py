import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from assemble_native_source_candidate import (OPEN_ITEMS, evidence_files, json_bytes,
                                               portuguese_chain, verified_package)
from bundle_verified_materials import build, digest_file


class SourceAssemblyTests(unittest.TestCase):
    def package(self, root):
        source = root / "source"; source.mkdir()
        original = source / "notice"; original.write_bytes(b"Original licence\r\n\xff\x00")
        spec = {"files": [{"source": str(original), "path": "upstream/NOTICE", "sha256": digest_file(original)}],
                "requiredPaths": ["upstream/NOTICE"], "unresolved": ["Irish original source remains open"]}
        receipt = build(spec, [source], root / "package")
        return root / "package/SourceMaterials.zip", receipt, original

    def rewrite(self, root, archive, receipt, mutate):
        with zipfile.ZipFile(archive) as source:
            entries = [(item.filename, source.read(item)) for item in source.infolist()]
        entries = mutate(entries)
        modified = root / "modified.zip"
        with zipfile.ZipFile(modified, "w") as target:
            for name, raw in entries:
                target.writestr(name, raw)
        changed = copy.deepcopy(receipt)
        changed.update(bytes=modified.stat().st_size, sha256=digest_file(modified), entries=len(entries))
        changed["manifestSHA256"] = hashlib.sha256(next(raw for name, raw in entries if name == "MANIFEST.json")).hexdigest()
        return modified, changed

    def test_complete_package_verifies_without_changing_original_bytes_or_status(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); package, receipt, original = self.package(root)
            before = digest_file(package)
            manifest = verified_package(package, receipt)
            self.assertEqual(manifest["unresolved"], receipt["unresolved"])
            self.assertEqual(before, digest_file(package))
            with zipfile.ZipFile(package) as archive:
                self.assertEqual(archive.read("upstream/NOTICE"), original.read_bytes())

    def test_changed_archive_and_inner_member_cannot_be_accepted_by_only_updating_outer_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); package, receipt, _ = self.package(root)
            modified, changed = self.rewrite(root, package, receipt, lambda entries: [(name, b"tampered" if name == "upstream/NOTICE" else raw) for name, raw in entries])
            with self.assertRaises(ValueError): verified_package(modified, receipt)
            with self.assertRaises(ValueError): verified_package(modified, changed)

    def test_unlisted_paths_aliases_and_traversal_fail_before_extraction(self):
        for bad in ["../escape", "/absolute", "UPSTREAM/NOTICE", "extra"]:
            with self.subTest(bad=bad), tempfile.TemporaryDirectory() as directory:
                root = Path(directory).resolve(); package, receipt, _ = self.package(root)
                modified, changed = self.rewrite(root, package, receipt, lambda entries: entries + [(bad, b"bad")])
                with self.assertRaises(ValueError): verified_package(modified, changed)
                self.assertFalse((root / "escape").exists())

    def test_declared_notice_and_historical_limitations_are_not_dropped(self):
        for operation in ("required", "limitations"):
            with self.subTest(operation=operation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory).resolve(); package, receipt, _ = self.package(root)
                def mutate(entries):
                    result = []
                    for name, raw in entries:
                        if name == "MANIFEST.json":
                            data = json.loads(raw)
                            if operation == "required": data["requiredPaths"].append("COPYING")
                            else: data["unresolved"] = []
                            raw = json_bytes(data)
                        result.append((name, raw))
                    return result
                modified, changed = self.rewrite(root, package, receipt, mutate)
                with self.assertRaises(ValueError): verified_package(modified, changed)

    def test_complete_evidence_ledger_rejects_changed_unlisted_and_symlink_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); file = root / "proof.json"; file.write_text("{}\n")
            (root / "SHA256SUMS").write_text(digest_file(file) + "  proof.json\n")
            self.assertEqual(set(evidence_files(root)), {"proof.json", "SHA256SUMS"})
            file.write_text("changed")
            with self.assertRaises(ValueError): evidence_files(root)
            file.write_text("{}\n"); (root / "extra").write_text("unlisted")
            with self.assertRaises(ValueError): evidence_files(root)
            (root / "extra").unlink(); (root / "alias").symlink_to(file)
            with self.assertRaises(ValueError): evidence_files(root)

    def chain(self, root):
        archive_hash = "a" * 64; rows = {"rows": 17, "sortedRowsSHA256": "b" * 64}
        tagger = {"generated": rows, "release": rows, "rowsEqual": True, "sourceArchiveSHA256": archive_hash}
        first = root / "tagger.json"; first.write_bytes(json_bytes(tagger))
        synth = {"source": rows, "synthesis": rows, "allRowsEqual": True, "sourceProofSHA256": digest_file(first),
                 "tagInventoryEqual": True, "synthesisTags": 3, "inventoryTags": 3}
        second = root / "synthesis.json"; second.write_bytes(json_bytes(synth))
        return first, second, archive_hash, synth

    def test_full_source_chain_requires_rows_tags_and_exact_prior_proof(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); first, second, archive_hash, synth = self.chain(root)
            proof = portuguese_chain(first, second, archive_hash)
            self.assertEqual(proof["rows"], 17)
            self.assertFalse(proof["spellingProven"])
            for key, value in [("sourceProofSHA256", "c" * 64), ("allRowsEqual", False), ("inventoryTags", 4),
                               ("synthesis", {"rows": 16, "sortedRowsSHA256": "b" * 64})]:
                changed = copy.deepcopy(synth); changed[key] = value; second.write_bytes(json_bytes(changed))
                with self.subTest(key=key), self.assertRaises(ValueError): portuguese_chain(first, second, archive_hash)
            second.write_bytes(json_bytes(synth))
            with self.assertRaises(ValueError): portuguese_chain(first, second, "d" * 64)

    def test_new_scope_keeps_resource_rights_and_application_installation_open(self):
        text = "\n".join(OPEN_ITEMS)
        for required in ["Irish", "FST/Gaelspell", "Ukrainian", "CC BY-NC-SA", "GPL", "LGPL", "installation", "spelling", "R14"]:
            self.assertIn(required, text)


if __name__ == "__main__":
    unittest.main()
