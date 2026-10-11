"""Check prepared text limits only; never upload or infer submission readiness."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent
results = []
for path in sorted(root.glob("metadata.*.json")):
    data = json.loads(path.read_text())
    limits = {"name": 30, "subtitle": 30, "promotionalText": 170, "description": 4000}
    counts = {}
    for field, limit in limits.items():
        value = data[field]
        assert isinstance(value, str) and value.strip(), field
        assert len(value) <= limit, (field, len(value), limit)
        counts[field] = {"characters": len(value), "limit": limit}
    assert len(data["name"]) >= 2
    keywords = data["keywords"]
    assert len(keywords.encode("utf-8")) <= 100
    terms = keywords.split(",")
    assert all(len(term) > 2 and term == term.strip() and " " not in term for term in terms)
    assert len({term.casefold() for term in terms}) == len(terms)
    assert not {"scriptum", "ulysses", "openai", "anthropic", "apple"}.intersection(term.casefold() for term in terms)
    assert data["readyForSubmission"] is False
    counts["keywords"] = {"characters": len(keywords), "utf8Bytes": len(keywords.encode("utf-8")), "byteLimit": 100}
    missing = [field for field in ("supportURL", "privacyPolicyURL", "reviewContact", "copyright", "price") if data[field] is None]
    results.append({"file": path.name, "locale": data["locale"], "textLimitsPass": True,
                    "counts": counts, "unresolvedSubmissionFields": missing, "readyForSubmission": False})
assert len(results) == 2
report = {"checked": "2026-10-11", "scope": "Local text limits only; no portal or feature acceptance", "locales": results}
(root / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(json.dumps(report, ensure_ascii=False, indent=2))
