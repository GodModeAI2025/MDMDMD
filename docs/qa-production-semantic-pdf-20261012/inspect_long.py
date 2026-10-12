from pathlib import Path
import hashlib,json,re,subprocess,logging
from pypdf import PdfReader
root=Path(__file__).parent
fixtures=root/'long-mixed'
receipts=json.loads((fixtures/'PUBLIC_EXPORT_RECEIPTS.json').read_text())
results=[]
for expected in receipts:
    name=expected['theme']; path=fixtures/(name+'.pdf')
    assert hashlib.sha256(path.read_bytes()).hexdigest()==expected['pdfSHA256']
    reader=PdfReader(str(path),strict=True)
    text=''.join(page.extract_text() for page in reader.pages)
    normalized=''.join(text.split())
    markers=re.findall(r'P-C[1-4]-[0-9]+-END',normalized)
    assert markers==[f'P-C{c}-{p}-END' for c in range(1,5) for p in range(400)]
    assert text.count('🦊')==1796
    assert all(text.count(x)==1600 for x in ['Ελληνικά','русский'])
    textfile=root/(name+'-poppler.txt')
    extraction=subprocess.run(['/Users/markzimmermann/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/poppler/poppler/bin/pdftotext','-enc','UTF-8',str(path),str(textfile)],capture_output=True)
    assert extraction.returncode==0 and not extraction.stderr,extraction.stderr.decode()
    poppler=textfile.read_text()
    assert all(poppler.count(x)==1600 for x in ['日本語','Ελληνικά','русский','e\u0301'])
    assert poppler.count('🦊')==1796
    catalog=reader.trailer['/Root']; assert str(catalog['/Lang'])=='de-DE'
    assert '/StructTreeRoot' in catalog and catalog['/MarkInfo']['/Marked'].value is True
    assert len(reader.pages)==expected['pages']
    roles={}
    def visit(value):
        if isinstance(value,list):
            for item in value:visit(item)
        elif hasattr(value,'get_object'):
            item=value.get_object()
            if hasattr(item,'get'):
                role=item.get('/S')
                if role:roles[str(role)]=roles.get(str(role),0)+1
                child=item.get('/K')
                if child is not None:visit(child)
    visit(catalog['/StructTreeRoot'])
    assert roles.get('/Figure',0)==48
    assert roles.get('/Table',0)==16
    assert roles.get('/Note',0)==4
    checks=[]
    for label,index in [('first',0),('middle',len(reader.pages)//2),('last',len(reader.pages)-1)]:
        prefix=root/(name+'-'+label)
        proc=subprocess.run(['/Users/markzimmermann/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin/override/pdftoppm','-f',str(index+1),'-l',str(index+1),'-singlefile','-scale-to','1200','-png',str(path),str(prefix)],capture_output=True)
        assert proc.returncode==0,proc.stderr.decode()
        assert not proc.stderr,proc.stderr.decode()
        checks.append({'page':index+1,'png':str(prefix)+'.png','sha256':hashlib.sha256(Path(str(prefix)+'.png').read_bytes()).hexdigest()})
    results.append({'theme':name,'pdf_sha256':expected['pdfSHA256'],'pages':len(reader.pages),'paragraph_markers':len(markers),'foxes':text.count('🦊'),'pypdf_japanese':text.count('日本語'),'pypdf_nfd_e_acute':text.count('e\u0301'),'poppler_japanese':poppler.count('日本語'),'poppler_nfd_e_acute':poppler.count('e\u0301'),'structure_roles':roles,'language':str(catalog['/Lang']),'rasters':checks})
(root/'independent-long-reader.json').write_text(json.dumps(results,indent=2,ensure_ascii=False)+'\n')
print(json.dumps([{k:v for k,v in r.items() if k not in ['rasters','structure_roles']} for r in results],ensure_ascii=False))
