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
    def runtime_inventory(self, root, home):
        jar = self.jar(root / "m2/com/example/leaf/1/leaf-1.jar", {})
        jar.with_suffix(".pom").write_text('<project><licenses><license><name>MIT</name></license></licenses></project>')
        classpath = root / "classpath"
        classpath.write_text(str(jar))
        return subprocess.run([sys.executable, "-B", str(SOURCE / "inventory_licenses.py"),
                               "--classpath", str(classpath), "--maven-repository", str(root / "m2"),
                               "--runtime-home", str(home), "--output", str(root / "notices")],
                              capture_output=True, text=True)

    def test_runtime_root_notices_and_identity_are_retained_byte_exactly(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "runtime"
            (home / "legal/java.base").mkdir(parents=True)
            (home / "lib").mkdir()
            original = {"LICENSE.txt": b"Root license\r\n", "LICENSE_NATIVEIMAGE.txt": b"Native image exception\n",
                        "THIRD_PARTY_LICENSE.txt": "Third-party terms: Grüße\n".encode(),
                        "legal/java.base/LICENSE": b"JDK terms\n"}
            for name, raw in original.items():
                (home / name).write_bytes(raw)
            (home / "release").write_bytes(b'JAVA_VERSION="17.0.3"\r\n')
            (home / "lib/src.zip").write_bytes(b"Bundled source archive fixture")
            (home / "Copyright.class").write_bytes(b"Not license text")
            result = self.runtime_inventory(root, home)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads((root / "notices/INVENTORY.json").read_text())
            for name, raw in original.items():
                retained = next(row for row in report["supplementalNotices"] if row["origin"].endswith(":" + name))
                self.assertEqual((root / "notices" / retained["retainedFile"]).read_bytes(), raw)
            identity = report["runtimeIdentity"]
            self.assertEqual(set(identity["rootNoticeFiles"]), set(original) - {"legal/java.base/LICENSE"})
            self.assertEqual((root / "notices" / identity["releaseFile"]).read_bytes(), (home / "release").read_bytes())
            self.assertEqual(identity["bundledJavaSourceArchive"]["sha256"], hashlib.sha256((home / "lib/src.zip").read_bytes()).hexdigest())
            self.assertFalse(report["nativeRuntimeSDKCovered"])

    def test_missing_native_image_exception_refuses_a_completed_runtime_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "runtime"
            home.mkdir()
            for name in ["release", "LICENSE.txt", "THIRD_PARTY_LICENSE.txt"]:
                (home / name).write_bytes(b"Present")
            result = self.runtime_inventory(root, home)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("LICENSE_NATIVEIMAGE.txt", result.stderr)
            self.assertFalse((root / "notices/INVENTORY.json").exists())

    def test_existing_inventory_is_not_overwritten_or_mixed_with_new_notices(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            existing = root / "notices"
            existing.mkdir()
            (existing / "INVENTORY.json").write_bytes(b"Prior retained evidence\r\n")
            result = self.runtime_inventory(root, root / "unused-runtime")
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((existing / "INVENTORY.json").read_bytes(), b"Prior retained evidence\r\n")
            self.assertEqual([p.name for p in existing.iterdir()], ["INVENTORY.json"])

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
