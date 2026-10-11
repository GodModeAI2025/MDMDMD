from pathlib import Path
from pypdf import PdfReader
from collections import Counter
import json,hashlib,re,logging,time,unicodedata,subprocess
root=Path(__file__).parent; fixtures=root/'fixtures-source-text'
expected=json.loads((fixtures/'INPUT_RECEIPT.json').read_text())
receipts=json.loads((fixtures/'PUBLIC_EXPORT_RECEIPTS.json').read_text())
class NoWarnings(logging.Handler):
 def emit(self,record):raise AssertionError(record.getMessage())
logging.getLogger('pypdf').addHandler(NoWarnings())
results=[]
for receipt in receipts:
 started=time.monotonic();path=fixtures/(receipt['theme']+'.pdf');data=path.read_bytes()
 assert hashlib.sha256(data).hexdigest()==receipt['pdfSHA256']
 pdf=PdfReader(path,strict=True);assert len(pdf.pages)==receipt['pages']
 extraction=subprocess.run(['/opt/homebrew/bin/pdftotext','-raw','-enc','UTF-8',str(path),'-'],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=60)
 assert not extraction.stderr
 text=extraction.stdout.decode('utf-8');norm=unicodedata.normalize('NFC',''.join(text.split()))
 markers=re.findall(r'P-C[1-4]-[0-9]+-END',norm)
 assert markers==[f'P-C{c}-{p}-END' for c in range(1,5) for p in range(400)]
 assert text.count('🦊')==expected['foxes']
 for token in ('日本語','Ελληνικά','русский','café'):assert norm.count(token)==1600,(receipt['theme'],token,norm.count(token))
 for token in ('(toc)','[^literal]'):assert norm.count(token)==16
 for c in range(1,5):assert norm.count(f'Note-C{c}-END')==1
 source_spans=[]
 roles=Counter();figures=[];headers=[];tables=[]
 def walk(node):
  node=node.get_object() if hasattr(node,'get_object') else node
  if isinstance(node,list):
   for n in node:walk(n)
  elif isinstance(node,dict):
   role=str(node.get('/S',''));roles[role]+=bool(role)
   if role=='/Span' and '/ActualText' in node:source_spans.append(str(node['/ActualText']))
   if role=='/Figure':figures.append(node)
   if role=='/TH':headers.append(node)
   if role=='/Table':tables.append(node)
   if '/K' in node:walk(node['/K'])
 catalog=pdf.trailer['/Root'];assert catalog['/Lang']=='de-DE'
 walk(catalog['/StructTreeRoot']['/K'])
 source_norm=unicodedata.normalize('NFC',''.join(''.join(source_spans).split()))
 assert re.findall(r'P-C[1-4]-[0-9]+-END',source_norm)==markers
 assert source_norm.count('日本語')==1600 and source_norm.count('🦊')==expected['foxes']
 assert len(figures)==expected['figures'] and len(tables)==expected['tables']
 assert roles['/Note']==4 and roles['/TR']==144 and roles['/TD']==256 and len(headers)==32
 assert all('/Alt' in f and str(f['/Alt']) for f in figures)
 assert all(h['/A']['/Scope']=='/Column' and h['/A']['/O']=='/Table' for h in headers)
 assert all(all(x.get_object().get('/S')=='/TR' for x in table['/K']) for table in tables)
 external=[]
 for page in pdf.pages:
  for ref in page.get('/Annots',[]):
   annotation=ref.get_object()
   if '/A' in annotation and '/URI' in annotation['/A']:external.append(str(annotation['/A']['/URI']))
 assert sorted(external)==sorted(f'https://example.com/C{c}/S{s}' for c in range(1,5) for s in range(4))
 dimensions=[float(pdf.pages[0].mediabox.width),float(pdf.pages[0].mediabox.height)]
 expected_dimensions=(612,792) if receipt['theme'].startswith('letter') else (595.2756,841.8898)
 assert all(abs(a-b)<0.01 for a,b in zip(dimensions,expected_dimensions))
 results.append({'theme':receipt['theme'],'pages':len(pdf.pages),'sha256':receipt['pdfSHA256'],'paragraphMarkers':len(markers),'foxes':text.count('🦊'),'unicodeLanguagesChecked':['Japanese','Greek','Russian','French'],'figures':len(figures),'figureAlternatives':True,'tables':len(tables),'columnHeaders':len(headers),'externalImageLinks':len(external),'logicalTableParents':True,'catalogLanguage':str(catalog['/Lang']),'dimensions':dimensions,'readerWarnings':0,'textReader':'Poppler pdftotext 26.04 honors ActualText','sourceBackedSpans':len(source_spans),'rawCMapSampleJapaneseCount':pdf.pages[2].extract_text().count('日本語'),'rawCMapSampleRadicalCount':pdf.pages[2].extract_text().count('⽇本語'),'seconds':time.monotonic()-started})
 (root/'INDEPENDENT_READER_RESULT.json').write_text(json.dumps(results,indent=2,ensure_ascii=False))
 print(f"{receipt['theme']}: PASS",flush=True)
print('All long mixed manuscripts independently verified.',flush=True)
