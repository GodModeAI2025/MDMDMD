import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from lxml import etree
from select_upstream_examples import literal, select
from annotate_upstream_examples import annotate
from verify_upstream_parity import verify


class SelectionSafetyTests(unittest.TestCase):
    def test_utf16_marker_keeps_combining_and_emoji_prefix(self):
        example = etree.fromstring("<example>  👩🏽‍💻 café <marker>falsch</marker> bleibt.  </example>".encode())
        value = literal(example, True)
        self.assertEqual(value["source"], "👩🏽‍💻 café falsch bleibt.")
        self.assertEqual(value["offset"], len("👩🏽‍💻 café ".encode("utf-16-le")) // 2)
        self.assertEqual(value["length"], 6)

    def test_external_entity_example_is_not_simplified_or_resolved(self):
        parser = etree.XMLParser(resolve_entities=False, load_dtd=False, no_network=True)
        xml = b'<!DOCTYPE example [<!ENTITY payload SYSTEM "file:///nonexistent/private-source">]><example>&payload; <marker>word</marker></example>'
        value = etree.fromstring(xml, parser)
        self.assertIsNone(literal(value, True))

    def test_disabled_ancestor_and_unpaired_rules_do_not_enter_selection(self):
        xml = """<rules><category id="GRAMMAR" name="Grammar" type="grammar">
<rulegroup id="OFF" default="off"><rule><example correction="good"><marker>bad</marker></example><example>good</example></rule></rulegroup>
<rule id="TEMP" default="temp_off"><example correction="good"><marker>bad</marker></example><example>good</example></rule>
<rulegroup id="ACTIVE"><rule>
<example correction="good">A <marker>bad</marker> sentence.</example>
<example>A good sentence.</example>
</rule></rulegroup>
<rule id="UNPAIRED"><example correction="good"><marker>bad</marker></example></rule>
</category></rules>"""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); path = root / "org/languagetool/rules/en/grammar.xml"
            path.parent.mkdir(parents=True); path.write_text(xml)
            selected = select(root, ["en-US"], 5)
            self.assertEqual([r["ruleID"] for r in selected["records"]], ["ACTIVE", "ACTIVE"])
            raw = json.dumps(selected).encode()
            annotations = annotate(root, raw)
            self.assertEqual(annotations["records"], [{"corrections": ["good"]}, {"corrections": None}])
            path.write_text(xml.replace("good", "other"))
            with self.assertRaises(ValueError):
                annotate(root, raw)

    def test_path_traversal_language_is_rejected(self):
        with self.assertRaises(ValueError):
            select(Path("/"), ["../../en"], 5)


class EvidenceVerificationTests(unittest.TestCase):
    def fixture(self):
        corpus = {"records": [
            {"language": "en-US", "ruleID": "XML", "ruleLine": 1, "sourceLine": 2,
             "expect": "present", "offset": 0, "length": 3, "source": "bad"},
            {"language": "en-US", "ruleID": "XML", "ruleLine": 1, "sourceLine": 3,
             "expect": "absent", "source": "good"}]}
        raw = json.dumps(corpus).encode()
        annotations = {"selectionSHA256": hashlib.sha256(raw).hexdigest(),
                       "records": [{"corrections": ["good"]}, {"corrections": None}]}
        response = {"warnings": {"incompleteResults": False}, "matches": [
            {"rule": {"id": "OVERLAP"}, "offset": 0, "length": 3,
             "replacements": [{"value": "good"}], "message": "Explanation"}]}
        empty = {"warnings": {"incompleteResults": False}, "matches": []}
        native = []
        for i, (text, result) in enumerate([("bad", response), ("good", empty)]):
            native.append({"index": i, "language": "en-US", "ruleID": "XML",
                "expectation": "present" if i == 0 else "absent",
                "passed": True, "strictXMLIDPassed": i == 1,
                "selectedRuleID": "OVERLAP" if i == 0 else None,
                "findings": [{"ruleID": "OVERLAP", "offset": 0, "length": 3,
                              "kind": "grammar", "replacements": ["good"]}] if i == 0 else [],
                "nativeCalls": [{"submittedTextSHA256": hashlib.sha256(text.encode()).hexdigest(),
                                 "language": "en-US", "responseJSON": json.dumps(result)}],
                "manualRequired": False, "manualProtectionVerified": False,
                "correctionAdmitted": i == 0, "staleRevisionRejected": i == 0,
                "correctionClearedTarget": True if i == 0 else None})
        jvm = [{"language": "en-US", "response": response}, {"language": "en-US", "response": empty}]
        projection = {"records": [{"language": "en-US", "source": text} for text in ["bad", "good"]]}
        return raw, annotations, native, jvm, projection

    def test_full_reference_and_source_backed_overlap_are_required(self):
        args = self.fixture()
        self.assertTrue(verify(*args)["passed"])
        changed = copy.deepcopy(args)
        changed[3][0]["response"]["matches"][0]["message"] = "Different explanation"
        self.assertFalse(verify(*changed)["passed"])
        changed = copy.deepcopy(args)
        changed[1]["records"][0]["corrections"] = ["unsupported"]
        self.assertFalse(verify(*changed)["passed"])

    def test_projection_corruption_is_rejected(self):
        args = self.fixture()
        args[4]["records"][0]["source"] = "another request"
        self.assertFalse(verify(*args)["passed"])

    def test_manual_only_case_cannot_be_counted_as_applied(self):
        args = self.fixture()
        args[2][0].update(manualRequired=True, manualProtectionVerified=True, correctionAdmitted=True)
        self.assertFalse(verify(*args)["passed"])

    def test_incomplete_response_is_not_a_pass(self):
        args = self.fixture()
        args[3][0]["response"]["warnings"]["incompleteResults"] = True
        self.assertFalse(verify(*args)["passed"])

    def test_negative_control_cannot_hide_observed_overlapping_id(self):
        args = self.fixture()
        args[2][1]["findings"] = [args[2][0]["findings"][0]]
        self.assertFalse(verify(*args)["passed"])


if __name__ == "__main__":
    unittest.main()
