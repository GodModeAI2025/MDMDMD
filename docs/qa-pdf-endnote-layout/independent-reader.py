"""Independent exact-fixture text and PDF logical-structure readback."""
import hashlib
import json
import pathlib
import subprocess
from pypdf import PdfReader

root = pathlib.Path(__file__).resolve().parent
results = []

def structure_elements(value):
    value = value.get_object() if hasattr(value, "get_object") else value
    if isinstance(value, list):
        for item in value:
            yield from structure_elements(item)
    elif isinstance(value, dict):
        if "/S" in value:
            yield value
        if "/K" in value:
            yield from structure_elements(value["/K"])

for path in sorted((root / "after").glob("*.pdf")):
    reader = PdfReader(path, strict=True)
    text = subprocess.check_output(["/opt/homebrew/bin/pdftotext", str(path), "-"], text=True)
    elements = list(structure_elements(reader.trailer["/Root"].get("/StructTreeRoot", {})))
    notes = [e for e in elements if e.get("/S") == "/Note"]
    if path.stem != "plain":
        assert len(notes) == 1
        assert not any(e.get("/S") in ("/LI", "/LBody") for e in structure_elements(notes[0]))
        number = [e for e in structure_elements(notes[0]) if e.get("/ActualText") == "1."]
        assert len(number) == 1
    if path.stem in ("plain", "tagged"):
        assert text.count("NoteStart") == text.count("NoteTail.") == text.count("🦊") == 1
        assert text.count("Mehrsprachiger") == 240
        assert text.count("français") == text.count("ελληνικά.") == 240
        links = [a.get_object() for page in reader.pages for a in page.get("/Annots", [])]
        actions = [a["/A"].get_object() for a in links if "/A" in a]
        assert len([a for a in actions if "/URI" in a and str(a["/URI"]) == "https://example.com/note"]) == 1
        if notes:
            paragraphs = [e for e in structure_elements(notes[0]) if e.get("/S") == "/P"]
            assert len(paragraphs) == 2
    else:
        for witness in ("BodyWitness", "QuoteWitness", "HeaderWitness", "CellWitness"):
            assert text.count(witness) == 1
        figures = [e for e in structure_elements(notes[0]) if e.get("/S") == "/Figure"]
        assert len(figures) == (0 if path.stem == "rich-0" else 1)
        if figures:
            assert figures[0].get("/Alt") in ("Note photograph", "Image-first note")
        assert any(e.get("/S") == "/BlockQuote" for e in structure_elements(notes[0]))
        assert any(e.get("/S") == "/Table" for e in structure_elements(notes[0]))
        if path.stem == "rich-0":
            assert any(e.get("/S") == "/Code" for e in structure_elements(notes[0]))
            assert text.count("CodeWitness") == 1
        elif path.stem == "rich-1":
            assert text.count("BeforeImageWitness") == text.count("AfterImageWitness") == 1
        else:
            assert text.count("ImageFirstWitness") == 1
    results.append({"file": str(path.relative_to(root)), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                    "pages": len(reader.pages), "logicalNotes": len(notes), "textAndStructureVerified": True})
assert len(results) == 5
print(json.dumps(results, indent=2))
