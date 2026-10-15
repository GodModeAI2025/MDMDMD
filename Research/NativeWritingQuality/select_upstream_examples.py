#!/usr/bin/env python3
"""Select literal positive/negative upstream examples before observing results.

Reads the already pinned LT resource tree offline; never resolves external XML
entities, rewrites prose or removes a failing example after engine execution.
Requires lxml for source-line provenance and explicit entity handling.
"""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re
from lxml import etree


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def literal(example, incorrect):
    # Only plain prose and marker elements. Dynamic/entity examples need their
    # original upstream test harness and are not silently simplified here.
    if any(not isinstance(n.tag, str) or n.tag not in ("example", "marker") for n in example.iter()):
        return None
    markers = example.findall("marker")
    if incorrect and (len(markers) != 1 or len(markers[0])):
        return None
    raw = "".join(example.itertext())
    source = raw.strip()
    if not source or len(source) > 400 or any(c in source for c in "`*_[]<>\\\0"):
        return None
    if not incorrect:
        return {"source": source}
    marker = markers[0]
    prefix = example.text or ""
    for child in example:
        if child is marker:
            break
        prefix += "".join(child.itertext()) + (child.tail or "")
    start = len(prefix) - (len(raw) - len(raw.lstrip()))
    marked = "".join(marker.itertext())
    if not marked or start < 0 or source[start:start + len(marked)] != marked:
        return None
    return {"source": source, "offset": len(source[:start].encode("utf-16-le")) // 2,
            "length": len(marked.encode("utf-16-le")) // 2, "marked": marked}


def select(resources, languages, groups_per_language):
    records, inputs, counts = [], [], []
    parser = etree.XMLParser(resolve_entities=False, load_dtd=False, no_network=True, recover=False)
    for language in languages:
        if not re.fullmatch(r"[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*", language):
            raise ValueError("Invalid language code")
        primary = language.split("-")[0]
        relative = "org/languagetool/rules/" + primary + "/grammar.xml"
        path = resources / relative
        if not path.is_file():
            counts.append({"language": language, "selectedRuleIDs": [], "reason": "No pinned grammar.xml"})
            continue
        raw = path.read_bytes()
        fingerprint = sha(raw)
        document = etree.fromstring(raw, parser)
        inputs.append({"path": relative, "sha256": fingerprint})
        categories = defaultdict(list)
        seen = set()
        for rule in document.findall(".//rule"):
            scope = [rule, *rule.iterancestors()]
            if any(n.get("default") in ("off", "temp_off") for n in scope):
                continue
            rule_id = next((n.get("id") for n in scope if n.tag in ("rule", "rulegroup") and n.get("id")), None)
            category = next((n for n in scope if n.tag == "category"), None)
            if not rule_id or rule_id in seen or category is None:
                continue
            positive = negative = None
            for example in rule.findall("example"):
                incorrect = example.get("correction") is not None or example.get("type") == "incorrect"
                value = literal(example, incorrect)
                if value is None:
                    continue
                value["sourceLine"] = example.sourceline
                if incorrect and positive is None:
                    positive = value
                elif not incorrect and negative is None and example.get("type") != "triggers_error":
                    negative = value
            if positive is None or negative is None:
                continue
            seen.add(rule_id)
            identity = {"language": language, "ruleID": rule_id, "categoryID": category.get("id"),
                        "categoryName": category.get("name"), "categoryType": category.get("type"),
                        "xml": relative, "xmlSHA256": fingerprint, "ruleLine": rule.sourceline}
            categories[category.get("id", "")].append((identity, positive, negative))
        # Prefer declared grammar/style intent, then distribute across the
        # remaining original categories. Order is independent of engine output.
        def priority(key):
            first = categories[key][0][0]
            kind = first["categoryType"]
            grammatical = "GRAMMAR" in key or "AGREEMENT" in key
            return (0 if kind == "grammar" or grammatical else 1 if kind in ("style", "register", "duplication") else 2, key)
        keys = sorted(categories, key=priority)
        chosen = []
        index = 0
        while len(chosen) < groups_per_language:
            added = False
            for key in keys:
                if index < len(categories[key]) and len(chosen) < groups_per_language:
                    chosen.append(categories[key][index]); added = True
            if not added:
                break
            index += 1
        for identity, positive, negative in chosen:
            records.append({**identity, **positive, "expect": "present"})
            records.append({**identity, **negative, "expect": "absent"})
        counts.append({"language": language, "eligibleDistinctRuleIDs": len(seen),
                       "selectedRuleIDs": [x[0]["ruleID"] for x in chosen]})
    return {"policy": "Up to five distinct active rule IDs per language, original positive/negative example pairs, category round robin before runtime observation. Outer XML whitespace stripped; original prose otherwise unchanged. No external entities or dynamic markup.",
            "engine": "LanguageTool 6.6", "ruleGroupsPerLanguage": groups_per_language,
            "inputs": inputs, "selection": counts, "records": records,
            "scope": "Bounded upstream regression selection, not exhaustive linguistic quality or app delivery acceptance"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resources", type=Path, required=True)
    parser.add_argument("--language-fixture", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    languages = [r["language"] for r in json.loads(args.language_fixture.read_text())["records"]]
    report = select(args.resources, languages, 5)
    with args.output.open("x", encoding="utf-8") as output:
        json.dump(report, output, ensure_ascii=False, indent=2); output.write("\n")
    print(json.dumps({"records": len(report["records"]), "languagesWithPairs": sum(bool(x["selectedRuleIDs"]) for x in report["selection"]),
                      "selectionSHA256": sha(args.output.read_bytes()), "emptyLanguages": [x["language"] for x in report["selection"] if not x["selectedRuleIDs"]]}, indent=2))


if __name__ == "__main__":
    main()
