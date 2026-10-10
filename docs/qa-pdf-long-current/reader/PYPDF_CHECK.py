from pathlib import Path
import sys,json,hashlib
from pypdf import PdfReader
pdf=Path(sys.argv[1]); output=Path(sys.argv[2]);output.mkdir(parents=True,exist_ok=True)
r=PdfReader(pdf)
texts=[p.extract_text() for p in r.pages]
text="\n".join(texts)
# Whitespace differs legitimately at rendered line/page boundaries.
flat=" ".join(text.split())
phrase="Absatz des langen Manuskripts: Quellen, Gedanken und eine präzise Frage."
count=flat.count(phrase)
receipt={"artifactSHA256":hashlib.sha256(pdf.read_bytes()).hexdigest(),"bytes":pdf.stat().st_size,"pages":len(r.pages),"emptyTextPages":[i+1 for i,t in enumerate(texts) if not t.strip()],"expectedRepeatedParagraphs":8000,"extractedRepeatedParagraphs":count,"allRepeatedParagraphsPresent":count==8000,"headingsPresent":all(h in flat for h in ["Kapitel Eins","Zweiter Abschnitt"]),"codePresent":"let code = 42" in flat,"foxCount":text.count("🦊"),"expectedFoxCount":8001,"pageBoxes":sorted({tuple(float(x) for x in p.mediabox) for p in r.pages}),"taggedStructure":bool(r.trailer["/Root"].get("/StructTreeRoot")),"scope":"Independent extraction of this actual synthetic native PDF; visual pages inspected separately. Not complete theme/accessibility/Files acceptance."}
(output/"READER_CHECK.json").write_text(json.dumps(receipt,indent=2)+"\n")
(output/"EXTRACTED_TEXT.txt").write_text(text)
print(json.dumps(receipt,indent=2))
