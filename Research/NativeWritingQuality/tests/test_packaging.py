import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

SOURCE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SOURCE))


class PackagingTests(unittest.TestCase):
    def run_pack(self, root, jars, name):
        classpath = root / (name + ".classpath")
        classpath.write_text(":".join(map(str, jars)))
        output = root / name
        result = subprocess.run([sys.executable, "-B", str(SOURCE / "pack_resources.py"),
                                 "--classpath", str(classpath), "--output", str(output)],
                                capture_output=True, text=True)
        return result, output

    def jar(self, path, entries):
        path.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(path, "w") as archive:
            for name, content in entries.items():
                archive.writestr(name, content)
        return path

    def test_exact_round_trip_and_reproducible_package(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            content = "ÄÖÜ, 🦊, العربية\n".encode()
            jar = self.jar(root / "data.jar", {"org/languagetool/resource/de/example.txt": content,
                                                "org/languagetool/rules/de/grammar.xml": b"<rules/>"})
            first, a = self.run_pack(root, [jar], "first")
            second, b = self.run_pack(root, [jar], "second")
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual((a / "LanguageTool-6.6-resources.zip").read_bytes(), (b / "LanguageTool-6.6-resources.zip").read_bytes())
            self.assertEqual((a / "resources/org/languagetool/resource/de/example.txt").read_bytes(), content)

    def test_rejects_traversal_before_extraction(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            jar = self.jar(root / "data.jar", {"org/languagetool/resource/../../../../escaped": b"bad"})
            result, output = self.run_pack(root, [jar], "out")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Unsafe resource path", result.stderr)
            self.assertFalse((root / "escaped").exists())
            self.assertFalse((output / "resources").exists())

    def test_conflicting_resources_are_not_silently_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            name = "org/languagetool/resource/en/example.txt"
            jars = [self.jar(root / "a.jar", {name: b"one"}), self.jar(root / "b.jar", {name: b"two"})]
            result, _ = self.run_pack(root, jars, "out")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Conflicting classpath resources", result.stderr)

    def test_pinned_irish_variants_both_remain_in_classpath_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            name = "org/languagetool/resource/ga/filter-archaic.txt"
            jars = [self.jar(root / "a.jar", {name: b"one", "org/languagetool/rules/ga/grammar.xml": b"<rules/>"}),
                    self.jar(root / "b.jar", {name: b"two"})]
            result, output = self.run_pack(root, jars, "out")
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads((output / "manifest.json").read_text())
            self.assertEqual([x["sha256"] for x in manifest["classPathRetained"][name]],
                             [hashlib.sha256(x).hexdigest() for x in [b"one", b"two"]])
            self.assertFalse((output / "resources" / name).exists())

    def test_classifier_jar_inherits_exact_parent_license_declaration(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            jar = self.jar(root / "m2/com/example/leaf/1/leaf-1-native.jar", {})
            jar.with_name("leaf-1.pom").write_text('<project><parent><groupId>com.example</groupId><artifactId>base</artifactId><version>1</version></parent></project>')
            parent = root / "m2/com/example/base/1/base-1.pom"
            parent.parent.mkdir(parents=True)
            parent.write_text('<project><licenses><license><name>MIT</name><url>https://example.invalid/license</url></license></licenses></project>')
            classpath = root / "classpath"
            classpath.write_text(str(jar))
            result = subprocess.run([sys.executable, "-B", str(SOURCE / "inventory_licenses.py"),
                                     "--classpath", str(classpath), "--maven-repository", str(root / "m2"),
                                     "--output", str(root / "notices")], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads((root / "notices/INVENTORY.json").read_text())
            self.assertEqual(report["unresolvedDeclarations"], [])
            self.assertEqual(report["artifacts"][0]["licenses"][0]["name"], "MIT")
            self.assertEqual(report["artifacts"][0]["declarationSource"]["sha256"], hashlib.sha256(parent.read_bytes()).hexdigest())


if __name__ == "__main__":
    unittest.main()
