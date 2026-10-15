import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "verify_ukrainian_generated.py"
spec = importlib.util.spec_from_file_location("ukrainian_generated", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class UkrainianGeneratedSourceTests(unittest.TestCase):
    def test_unicode_fields_preserved(self):
        raw = "Минки Минка noun:anim:f:v_rod:prop:fname\n".encode()
        row, tag = module.canonical_source_row(raw)
        self.assertEqual(row, "Минки\tМинка\tnoun:anim:f:v_rod:prop:fname\n".encode())
        self.assertEqual(tag, b"noun:anim:f:v_rod:prop:fname")

    def test_malformed_source_rows_are_rejected(self):
        for raw in [b"a b\n", b"a b c d\n", b"a  b c\n", b"a\tb c\n", b"a b c\r\n", b"a b c", b"a b \xff\n", b"a b c\0\n"]:
            with self.subTest(raw=raw), self.assertRaises((ValueError, UnicodeDecodeError)):
                module.canonical_source_row(raw)

    def test_synth_filter_preserves_upstream_prefix_semantics(self):
        for tag in [b"noun:subst", b"verb:vulg", b"noun:obsc", b"noun:vis", b"noun:visual"]:
            self.assertIsNotNone(module.EXCLUDE_SYNTH.search(b"word\tlemma\t" + tag + b"\n"))
        self.assertIsNone(module.EXCLUDE_SYNTH.search(b"word\tlemma\tnoun:slang\n"))

    def test_both_difference_directions_are_retained(self):
        with tempfile.TemporaryDirectory() as temp:
            a, b = Path(temp) / "source", Path(temp) / "binary"
            a.write_bytes(b"a\nc\nd\n")
            b.write_bytes(b"b\nc\ne\n")
            result = module.compare_sorted(a, b)
            self.assertFalse(result["contentEqual"])
            self.assertEqual(result["commonRows"], 1)
            self.assertEqual(result["sourceOnlyRows"], 2)
            self.assertEqual(result["binaryOnlyRows"], 2)
            self.assertEqual(result["sourceOnlySample"], ["a", "d"])
            self.assertEqual(result["binaryOnlySample"], ["b", "e"])

    def test_empty_or_equal_inputs(self):
        with tempfile.TemporaryDirectory() as temp:
            a, b = Path(temp) / "source", Path(temp) / "binary"
            for data in (b"", b"a\nb\n"):
                a.write_bytes(data)
                b.write_bytes(data)
                result = module.compare_sorted(a, b)
                self.assertTrue(result["contentEqual"])
                self.assertEqual(result["commonRows"], len(data.splitlines()))


if __name__ == "__main__":
    unittest.main()
