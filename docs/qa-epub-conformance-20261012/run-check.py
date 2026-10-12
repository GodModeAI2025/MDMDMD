from pathlib import Path
import subprocess, json, hashlib, sys, xml.etree.ElementTree as E, zipfile
root = Path(__file__).resolve().parent
base = Path('/private/tmp/SkriptumAppleBroker/debug').resolve()
java = root.parent / 'writing-quality-runtime/jdk-21.0.12.1+1-jre/Contents/Home/bin/java'
phase = sys.argv[1]
cmd=['xcrun','swiftc',str(root/'generator.swift'),'-I',str(base),'-module-cache-path','/private/tmp/scriptum-epub-modulecache']
for rel in ['swift-cmark/src/include','swift-cmark/extensions/include','swift-markdown/Sources/CAtomic/include']:
 cmd+=['-I',str(Path('/private/tmp/SkriptumAppleBroker/checkouts')/rel)]
for target in ['SkriptumExport','Markdown','cmark-gfm','cmark-gfm-extensions','CAtomic']:
 obj = base/(target+'.o')
 assert obj.exists(), obj
 cmd.append(str(obj))
cmd+=['-framework','AppKit','-framework','PDFKit','-o',str(root/'generate')]
r=subprocess.run(cmd,capture_output=True,text=True)
(root/('generator-compile-'+phase+'.log')).write_text(r.stdout+r.stderr)
if r.returncode: raise SystemExit(r.returncode)
subprocess.run([str(root/'generate'),str(root/phase)],check=True)
results={}
for epub in sorted((root/phase).glob('*.epub')):
 report=root/(epub.stem+'-'+phase+'.json')
 r=subprocess.run([str(java),'-jar',str(root/'epubcheck-5.4.0/epubcheck.jar'),str(epub),'--json',str(report)],capture_output=True,text=True)
 (root/(epub.stem+'-'+phase+'.log')).write_text(r.stdout+r.stderr)
 j=json.loads(report.read_text())
 item={'sha256':hashlib.sha256(epub.read_bytes()).hexdigest(),'bytes':epub.stat().st_size,'exit':r.returncode,'messages':[{'id':m['ID'],'severity':m['severity'],'message':m['message']} for m in j['messages']]}
 if epub.stem.startswith('manuscript-'):
  with zipfile.ZipFile(epub) as z:
   assert z.testzip() is None
   content=E.fromstring(z.read('EPUB/content.xhtml'))
   nav=E.fromstring(z.read('EPUB/nav.xhtml'))
   text=''.join(content.itertext())
   ns={'h':'http://www.w3.org/1999/xhtml'}
   assert text.count('Absatz ')==1440 and text.count('🦊')==1440
   assert text.count('Café e\u0301')==1440
   assert len(content.findall('.//h:table',ns))==24
   assert len(content.findall('.//h:aside',ns))==24
   assert len(nav.findall('.//h:a',ns))==48
   item['independent_fidelity']={'chapters':24,'paragraphs':1440,'foxes':1440,'decomposed_unicode':1440,'tables':24,'footnotes':24,'toc_links':48}
 results[epub.name]=item
(root/(phase+'-summary.json')).write_text(json.dumps(results,indent=2,ensure_ascii=False)+'\n')
print(json.dumps(results,indent=2,ensure_ascii=False),flush=True)
if any(v['exit'] for v in results.values()): raise SystemExit(1)
