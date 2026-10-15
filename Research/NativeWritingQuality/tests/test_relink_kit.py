import copy
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare_native_relink_kit import INPUTS, publish, read_arguments
from relink_native_kit import build_command, sha, verify_kit


class RelinkKitTests(unittest.TestCase):
    def fixture(self, root):
        source = root / "source"; source.mkdir()
        records = []
        names = [INPUTS[k] for k in ("mac-object", "ios-object", "ios-fallbacks", "manifest")]
        names += [INPUTS[k] + "/fixture" for k in ("graal-home", "ios-runtime", "headers", "resources")]
        names += ["tools/build_frameworks.py", "tools/IOSRuntimeCompatibility.c", "tools/IOSRuntimeCompatibility-LICENSE.txt"]
        for index, name in enumerate(names):
            file = source / str(index); file.write_bytes((name + "\r\n🦊").encode() + b"\xff\x00")
            records.append((file, name, sha(file)))
        return source, records

    def test_relocated_kit_keeps_exact_bytes_and_recipe_uses_only_new_root(self):
        with tempfile.TemporaryDirectory() as value:
            root = Path(value).resolve(); _, records = self.fixture(root)
            kit = root / "kit"; publish(records, kit, {})
            moved = root / "different parent" / "relocated"
            moved.parent.mkdir(); shutil.copytree(kit, moved)
            shutil.rmtree(kit)
            manifest = verify_kit(moved)
            command = build_command(moved, root / "new output", manifest)
            self.assertTrue(all(str(kit) not in value for value in command))
            self.assertIn(str(moved / INPUTS["mac-object"]), command)
            for original, name, fingerprint in records:
                self.assertEqual((moved / name).read_bytes(), original.read_bytes())
                self.assertEqual(sha(moved / name), fingerprint)

    def test_source_mutation_is_rejected_before_creating_output(self):
        with tempfile.TemporaryDirectory() as value:
            root = Path(value).resolve(); _, records = self.fixture(root)
            records[0][0].write_bytes(b"changed")
            with self.assertRaises(ValueError): publish(records, root / "kit", {})
            self.assertFalse((root / "kit").exists())

    def test_input_and_runtime_mutations_are_rejected_before_compilation(self):
        with tempfile.TemporaryDirectory() as value:
            root = Path(value).resolve(); _, records = self.fixture(root)
            kit = root / "kit"; publish(records, kit, {})
            for name in (INPUTS["mac-object"], INPUTS["graal-home"] + "/fixture", "tools/build_frameworks.py"):
                file = kit / name; original = file.read_bytes(); file.write_bytes(b"changed")
                with self.subTest(name=name), self.assertRaises(ValueError): verify_kit(kit)
                file.write_bytes(original)
            verify_kit(kit)

    def test_symlink_inputs_ancestors_and_added_kit_entries_are_rejected(self):
        with tempfile.TemporaryDirectory() as value:
            root = Path(value).resolve(); source, records = self.fixture(root)
            link = root / "alias"; link.symlink_to(source, target_is_directory=True)
            changed = list(records); changed[0] = (link / records[0][0].name, records[0][1], records[0][2])
            with self.assertRaises(ValueError): publish(changed, root / "bad", {})
            kit = root / "kit"; publish(records, kit, {})
            (kit / "unexpected").write_bytes(b"unlisted")
            with self.assertRaises(ValueError): verify_kit(kit)
            (kit / "unexpected").unlink(); (kit / "alias").symlink_to(kit / "objects")
            with self.assertRaises(ValueError): verify_kit(kit)

    def test_duplicate_escape_and_existing_output_never_overwrite_evidence(self):
        with tempfile.TemporaryDirectory() as value:
            root = Path(value).resolve(); _, records = self.fixture(root)
            for name in ("../escape", "/absolute", "a/../escape", "OBJECTS/MACOS/GRAMMAR.O", "MANIFEST.json"):
                with self.subTest(name=name), self.assertRaises(ValueError):
                    publish(records + [(records[0][0], name, records[0][2])], root / "bad", {})
            kit = root / "kit"; publish(records, kit, {})
            original = (kit / "MANIFEST.json").read_bytes()
            with self.assertRaises(ValueError): publish(records, kit, {})
            self.assertEqual((kit / "MANIFEST.json").read_bytes(), original)
            with self.assertRaises(ValueError): build_command(kit, kit / "nested", verify_kit(kit))
            with self.assertRaises(ValueError): build_command(kit, root / "source", verify_kit(kit))

    def test_missing_manifest_members_and_unknown_recipe_inputs_are_rejected(self):
        with tempfile.TemporaryDirectory() as value:
            root = Path(value).resolve(); _, records = self.fixture(root)
            kit = root / "kit"; publish(records, kit, {})
            path = kit / "MANIFEST.json"; original = json.loads(path.read_text())
            for operation in ("removed", "unknown", "escape", "duplicate"):
                changed = copy.deepcopy(original)
                if operation == "removed": changed["files"].pop()
                if operation == "unknown": changed["inputs"]["shell"] = "anything"
                if operation == "escape": changed["inputs"]["headers"] = "../outside"
                if operation == "duplicate": changed["files"].append(changed["files"][0])
                path.write_text(json.dumps(changed))
                with self.subTest(operation=operation), self.assertRaises(ValueError): verify_kit(kit)

    def test_recorded_command_is_data_and_rejects_unknown_or_duplicate_flags(self):
        command = ["python3", "-B", "builder.py"]
        for key in INPUTS: command.extend(["--" + key, "/literal/input"])
        command += ["--output", "/literal/output"]
        self.assertEqual(read_arguments(command)["output"], Path("/literal/output"))
        for changed in (command + ["--output", "/other"], command + ["--execute", "anything"], command[:-1]):
            with self.assertRaises(ValueError): read_arguments(changed)


if __name__ == "__main__":
    unittest.main()
