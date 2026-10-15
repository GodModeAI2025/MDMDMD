import hashlib
import io
import json
import logging
import pathlib
import sys
from pypdf import PdfReader

path = pathlib.Path(sys.argv[1])
warnings = io.StringIO()
logging.getLogger("pypdf").addHandler(logging.StreamHandler(warnings))
reader = PdfReader(path, strict=True)
pages = list(reader.pages)
page_ids = {p.indirect_reference.idnum for p in pages}
root = reader.trailer["/Root"]["/StructTreeRoot"]
document = root["/K"]
assert document["/S"] == "/Document"

def children(node):
    value = node.get("/K", [])
    value = value.get_object() if hasattr(value, "get_object") else value
    return [v.get_object() if hasattr(v, "get_object") else v for v in (value if isinstance(value, list) else [value])]

def elements(node):
    return [v for v in children(node) if isinstance(v, dict) and "/S" in v]

headings = [v for v in elements(document) if v.get("/S") == "/H3"]
assert len(headings) == 1
heading = headings[0]
assert heading["/Lang"] == "de-DE"
assert [v["/S"] for v in elements(heading)] == ["/Span", "/Figure", "/Span", "/Figure", "/Span"]
assert [v["/Alt"] for v in elements(heading) if v["/S"] == "/Figure"] == ["First", "Second"]
assert all(v["/S"] != "/Figure" for v in elements(document))
annotations = [v.get_object() for p in pages for v in p.get("/Annots", [])]
annotation_ids = {v.indirect_reference.idnum for v in annotations}
structure_annotations = []
actual = []

def walk(node):
    for child in children(node):
        if not isinstance(child, dict):
            continue
        if "/S" in child:
            assert child["/P"].indirect_reference.idnum == node.indirect_reference.idnum
            if "/ActualText" in child:
                actual.append(str(child["/ActualText"]))
            walk(child)
        elif child.get("/Type") == "/MCR":
            assert child["/Pg"].indirect_reference.idnum in page_ids
        elif child.get("/Type") == "/OBJR":
            identifier = child["/Obj"].indirect_reference.idnum
            assert identifier in annotation_ids
            structure_annotations.append(identifier)

walk(document)
assert len(structure_annotations) == len(annotations) == 4
assert len(set(structure_annotations)) == len(annotations)
external = [v["/A"]["/URI"] for v in annotations if "/A" in v]
assert external == ["https://example.com/first", "https://example.com/second"]
internal = [v["/Dest"] for v in annotations if "/Dest" in v]
assert len(internal) == 2
assert all(v[0].idnum in page_ids and v[1] == "/XYZ" for v in internal)
text = "\n".join(p.extract_text() for p in pages)
assert all(v in text for v in ["Prefix", "Middle", "Suffix", "BodyOutsideHeading"])
assert text.count("🦊") == 1
assert not warnings.getvalue(), warnings.getvalue()
print(json.dumps({"sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "pages": len(pages),
    "headingRole": str(heading["/S"]), "headingChildren": [str(v["/S"]) for v in elements(heading)],
    "figureAlternatives": [str(v["/Alt"]) for v in elements(heading) if v["/S"] == "/Figure"],
    "annotationCount": len(annotations), "annotationsStructurallyOwnedExactlyOnce": True,
    "allStructureParentsValid": True, "allContentPagesValid": True,
    "text": text, "warnings": warnings.getvalue()}, ensure_ascii=False, indent=2))
