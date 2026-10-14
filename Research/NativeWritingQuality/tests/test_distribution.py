import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
import zipfile
import sys

SOURCE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SOURCE))
from notice_files import is_notice


def module(name):
    spec = importlib.util.spec_from_file_location(name, SOURCE / (name + ".py"))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


materials = module("collect_source_materials")
frameworks = module("build_frameworks")


class DistributionTests(unittest.TestCase):
    def test_compiled_code_is_not_a_license_even_when_its_name_matches(self):
        for name in ["CopyingImageHeapProvider.class", "AbstractCopyingImageHeapProvider.class", "JvmThreadMetrics.class", "LicenseChecker.java"]:
            self.assertFalse(is_notice(name, include_readmes=True))
        for name in ["META-INF/LICENSE", "COPYING.LESSER", "LICENSES-en.txt", "resource/12dicts-readme.html", "README_lexique.txt", "COPYRIGHT"]:
            self.assertTrue(is_notice(name, include_readmes=True))

    def archive(self, name, value=b"source", symlink=False):
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as archive:
            info = zipfile.ZipInfo(name)
            if symlink:
                info.create_system = 3
                info.external_attr = 0o120777 << 16
            archive.writestr(info, value)
        return data.getvalue()

    def test_source_archive_preserves_unicode_and_rejects_unsafe_entries(self):
        materials.validate_source(self.archive("source/Café.java", "你好".encode()))
        for invalid in ["../outside", "/absolute", "source/../../outside", "source\\outside"]:
            with self.subTest(path=invalid), self.assertRaises(ValueError):
                materials.validate_source(self.archive(invalid))
        with self.assertRaises(ValueError):
            materials.validate_source(self.archive("source/link", symlink=True))

    def test_classified_artifacts_use_unclassified_source_coordinates(self):
        with tempfile.TemporaryDirectory() as value:
            root = Path(value)
            jar = root / "group/component/1.2/component-1.2-data.jar"
            jar.parent.mkdir(parents=True)
            jar.touch()
            relative, artifact, version = materials.coordinates(jar, root)
            self.assertEqual((artifact, version), ("component", "1.2"))
            self.assertEqual(relative.as_posix(), "group/component/1.2/component-1.2-data.jar")
            with self.assertRaises(ValueError):
                materials.coordinates(jar, root / "other")

    def test_source_transport_refuses_non_maven_urls_before_network(self):
        for url in ["https://fixture.invalid/source.jar", "file:///tmp/source.jar", "http://repo.maven.apache.org/maven2/source.jar"]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                materials.download(url, 100)

    def test_framework_resources_reject_mutation_traversal_and_internal_symlinks(self):
        with tempfile.TemporaryDirectory() as value:
            root = Path(value).resolve()
            target = root / "data/file"
            target.parent.mkdir()
            target.write_bytes(b"original")
            record = {"path": "data/file", "bytes": 8, "sha256": hashlib.sha256(b"original").hexdigest()}
            self.assertEqual(frameworks.resource_records(root, {"resources": [record]}), [record])
            target.write_bytes(b"modified")
            with self.assertRaises(ValueError):
                frameworks.resource_records(root, {"resources": [record]})
            target.write_bytes(b"original")
            (root / "alias").symlink_to("data", target_is_directory=True)
            for path in ["../file", "data/./file", "alias/file"]:
                with self.subTest(path=path), self.assertRaises(ValueError):
                    frameworks.resource_records(root, {"resources": [{**record, "path": path}]})


if __name__ == "__main__":
    unittest.main()
