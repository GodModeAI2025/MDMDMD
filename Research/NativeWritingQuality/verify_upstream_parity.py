#!/usr/bin/env python3
"""Verify recorded native responses against the full JVM on identical projection.

This checks bounded integration parity. It does not turn 138 selected rule pairs
into an exhaustive grammar/style acceptance or hide XML-rule overlap differences.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical_matches(response):
    # Match ordering is not a correction semantic. Preserve every field and
    # duplicate, normalizing only JSON key and match-array ordering.
    return sorted(json.dumps(m, sort_keys=True, ensure_ascii=False) for m in response["matches"])


def verify(corpus_raw, annotations, native, jvm, projection):
    corpus = json.loads(corpus_raw)["records"]
    if annotations["selectionSHA256"] != sha(corpus_raw):
        raise ValueError("Annotations belong to another selection")
    if not (len(corpus) == len(native) == len(jvm) == len(projection["records"]) == len(annotations["records"])):
        raise ValueError("Incomplete or mismatched corpus")
    outcomes, overlaps, errors = [], [], []
    kinds, language_kinds = Counter(), {}
    intent_ids = {}
    for index, (expected, actual, reference, projected, annotated) in enumerate(
            zip(corpus, native, jvm, projection["records"], annotations["records"])):
        failures = []
        identity = expected["language"], expected["ruleLine"]
        if (actual["index"], actual["language"], actual["ruleID"], actual["expectation"]) != (
                index, expected["language"], expected["ruleID"], expected["expect"]):
            failures.append("Native record identity mismatch")
        calls = actual["nativeCalls"]
        if not calls:
            failures.append("No native response")
            response = {"matches": []}
        else:
            response = json.loads(calls[0]["responseJSON"])
            if calls[0]["submittedTextSHA256"] != sha(projected["source"].encode()):
                failures.append("Submitted projection mismatch")
            if calls[0]["language"] != expected["language"]:
                failures.append("Submitted language mismatch")
        if reference["language"] != expected["language"] or projected["language"] != expected["language"]:
            failures.append("Reference language mismatch")
        parity = canonical_matches(response) == canonical_matches(reference["response"])
        if not parity:
            failures.append("Full native/JVM match objects differ")
        for value in [response, reference["response"]]:
            if value.get("warnings", {}).get("incompleteResults") is not False:
                failures.append("Incomplete-results status is not explicitly false")
        if actual.get("error") is not None or actual["passed"] is not True:
            failures.append("Native correction/control outcome failed")
        if expected["expect"] == "present":
            selected = [m for m in actual["findings"] if m["ruleID"] == actual.get("selectedRuleID") and
                        (m["offset"], m["length"]) == (expected["offset"], expected["length"])]
            if len(selected) != 1:
                failures.append("No unique finding at original marker")
                selected = None
            else:
                selected = selected[0]
                intent_ids[identity] = {expected["ruleID"], selected["ruleID"]}
                kinds[selected["kind"]] += 1
                language_kinds.setdefault(expected["language"], set()).add(selected["kind"])
                if selected["ruleID"] != expected["ruleID"]:
                    corrections = set(annotated["corrections"] or [])
                    if not corrections.intersection(selected["replacements"]):
                        failures.append("Alternative ID lacks literal maintainer correction")
                    overlaps.append({"index": index, "language": expected["language"],
                        "xmlRuleID": expected["ruleID"], "fullEngineRuleID": selected["ruleID"],
                        "sourceLine": expected["sourceLine"], "fullEngineParity": parity})
            if actual["manualRequired"]:
                if not actual["manualProtectionVerified"] or actual["correctionAdmitted"]:
                    failures.append("Manual-only correction was not refused safely")
            elif selected and selected["replacements"]:
                if not all([actual["correctionAdmitted"], actual["staleRevisionRejected"],
                            actual.get("correctionClearedTarget") is True]):
                    failures.append("Automatic correction/revision/recheck evidence missing")
        else:
            ids = intent_ids.get(identity)
            if ids is None or any(m["ruleID"] in ids for m in actual["findings"]):
                failures.append("Negative control triggers the original or selected overlapping rule")
        outcomes.append({"index": index, "language": expected["language"], "passed": not failures,
                         "fullResponseParity": parity, "strictXMLIDPassed": actual["strictXMLIDPassed"],
                         "errors": failures})
        errors.extend({"index": index, "reason": error} for error in failures)
    return {
        "selectionSHA256": sha(corpus_raw), "records": len(corpus),
        "positiveCases": sum(r["expect"] == "present" for r in corpus),
        "negativeControls": sum(r["expect"] == "absent" for r in corpus),
        "languages": sorted({r["language"] for r in corpus}),
        "fullResponseParityCases": sum(r["fullResponseParity"] for r in outcomes),
        "strictXMLIDCases": sum(r["strictXMLIDPassed"] for r in outcomes),
        "safeAutomaticCorrections": sum(r["correctionAdmitted"] for r in native),
        "manualOnlySuggestions": sum(r["manualRequired"] for r in native),
        "manualProtectionVerified": sum(r["manualProtectionVerified"] for r in native),
        "positiveCasesWithoutSuggestion": sum(r["expectation"] == "present" and
            not r["correctionAdmitted"] and not r["manualRequired"] for r in native),
        "positiveKinds": dict(kinds),
        "languagesByKind": {kind: sorted(code for code, values in language_kinds.items() if kind in values)
                            for kind in sorted(kinds)},
        "xmlIdentityOverlaps": overlaps, "outcomes": outcomes,
        "passed": not errors, "errors": errors,
        "scope": "Bounded upstream integration, source/revision protection and full JVM parity; not exhaustive linguistic acceptance or app delivery."
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["corpus", "annotations", "native", "jvm", "projection", "output"]:
        parser.add_argument("--" + name, required=True, type=Path)
    args = parser.parse_args()
    native = [json.loads(line) for line in args.native.read_text().splitlines()]
    result = verify(args.corpus.read_bytes(), json.loads(args.annotations.read_text()), native,
                    json.loads(args.jvm.read_text()), json.loads(args.projection.read_text()))
    with args.output.open("x", encoding="utf-8") as file:
        json.dump(result, file, ensure_ascii=False, indent=2); file.write("\n")
    print(json.dumps({k: v for k, v in result.items() if k not in ("outcomes", "languagesByKind")}, ensure_ascii=False))
    raise SystemExit(0 if result["passed"] else 1)


if __name__ == "__main__":
    main()
