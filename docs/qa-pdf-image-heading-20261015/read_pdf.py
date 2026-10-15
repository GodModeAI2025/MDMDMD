import hashlib
import io
import json
import logging
import pathlib
import sys

from pypdf import PdfReader

path = pathlib.Path(sys.argv[1])
messages = io.StringIO()
handler = logging.StreamHandler(messages)
logging.getLogger("pypdf").addHandler(handler)
reader = PdfReader(path, strict=True)
pages = list(reader.pages)
page_numbers = {(p.indirect_reference.idnum, p.indirect_reference.generation): n for n, p in enumerate(pages)}
annotations = [ref.get_object() for page in pages for ref in page.get("/Annots", [])]
links = [a for a in annotations if a.get("/Subtype") == "/Link"]
internal = [a for a in links if "/Dest" in a]
external = [a for a in links if "/A" in a and "/URI" in a["/A"] and a["/A"]["/URI"] == "https://example.com/figure"]
assert len(internal) == 3, internal
assert len(external) == 1, external
# Quartz resolves the writer's named destinations into indirect destination arrays.
# Inspect the PDF destination objects, independent of the implementation's labels.
targets = []
for link in internal:
    destination = link["/Dest"]
    assert destination[1] == "/XYZ", destination
    page_ref = destination[0]
    page_number = page_numbers[(page_ref.idnum, page_ref.generation)]
    targets.append({"page": page_number, "x": float(destination[2]), "top": float(destination[3])})
image_top = float(external[0]["/Rect"][3])
assert sum(t["page"] == 0 and abs(t["top"] - image_top) < 0.01 for t in targets) == 2, targets
assert len({(t["page"], t["top"]) for t in targets}) == 2, targets
text = "\n".join(p.extract_text() for p in pages)
assert "BodyAfterImageHeading" in text and "BodyAfterTextHeading." in text, text
assert text.count("🦊") == 1, text

roles = []
alternatives = []
def visit(value):
    if isinstance(value, list):
        for item in value:
            visit(item)
        return
    if hasattr(value, "get_object"):
        value = value.get_object()
    if isinstance(value, dict):
        if "/S" in value:
            roles.append(str(value["/S"]))
        if "/Alt" in value:
            alternatives.append(str(value["/Alt"]))
        if "/K" in value:
            visit(value["/K"])

visit(reader.trailer["/Root"]["/StructTreeRoot"])
assert "/Document" in roles and "/Figure" in roles and "/H1" in roles
assert "ImageHeadingWitness" in alternatives
assert not messages.getvalue(), messages.getvalue()
print(json.dumps({
    "file": str(path),
    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    "pages": len(reader.pages),
    "internalTargets": targets,
    "imageHeadingDestination": {"page": 0, "top": image_top},
    "text": text,
    "imageAnnotationRect": [float(n) for n in external[0]["/Rect"]],
    "roles": roles,
    "figureAlternativeRetained": True,
    "strictReaderWarnings": messages.getvalue(),
}, indent=2, ensure_ascii=False))
