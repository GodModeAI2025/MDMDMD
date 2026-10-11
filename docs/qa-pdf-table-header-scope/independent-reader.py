from pathlib import Path
from pypdf import PdfReader
import json, logging
root=Path(__file__).parent
results=[]
class NoWarnings(logging.Handler):
    def emit(self, record):
        raise AssertionError(record.getMessage())
logging.getLogger('pypdf').addHandler(NoWarnings())
for name in ('table-de-DE','table-no-language'):
    before=root/(name+'-before.pdf'); after=root/(name+'.pdf')
    a=PdfReader(before,strict=True); b=PdfReader(after,strict=True)
    assert after.read_bytes().startswith(before.read_bytes())
    assert len(a.pages)==len(b.pages)>1
    for x,y in zip(a.pages,b.pages):
        assert x.get_contents().get_data()==y.get_contents().get_data()
        assert x.extract_text()==y.extract_text()
        assert x.mediabox==y.mediabox
    doc=b.trailer['/Root']['/StructTreeRoot']['/K']
    table=doc['/K']; rows=table['/K']
    assert len(rows)==101
    headers=[cell.get_object() for cell in rows[0].get_object()['/K']]
    assert len(headers)==2
    for cell in headers:
        assert cell['/S']=='/TH'
        assert cell['/A']=={'/O':'/Table','/Scope':'/Column'}
    for row in rows[1:]:
        for cell in row.get_object()['/K']:
            assert cell.get_object()['/S']=='/TD' and '/A' not in cell.get_object()
    assert b.trailer['/Root']['/Version']=='/1.5'
    lang=b.trailer['/Root'].get('/Lang')
    assert lang==('de-DE' if name=='table-de-DE' else None)
    text=''.join(p.extract_text() for p in b.pages)
    assert text.count('🦊')==100
    results.append({'name':name,'pages':len(b.pages),'logicalHeaders':2,'logicalRows':101,'foxes':100,'language':lang,'version':'1.5','originalBytesRetained':True,'pageStreamsAndTextEqual':True})
print(json.dumps(results,indent=2,ensure_ascii=False))
