from pathlib import Path
import hashlib,json,subprocess,tempfile
from PIL import Image
from pypdf import PdfReader

root=Path(__file__).resolve().parent
repository=root.parents[1]
fixtures=repository/'docs/qa-heading-media/fixtures'
renderers={
 'bundled-splash':'/Users/markzimmermann/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin/override/pdftoppm',
 'homebrew-splash':'/opt/homebrew/bin/pdftoppm',
 'homebrew-cairo':'/opt/homebrew/bin/pdftocairo',
}
results=[]
with tempfile.TemporaryDirectory(prefix='scriptum-reader-proof-',dir='/private/tmp') as tmp:
 for pdf in sorted(fixtures.glob('after-*.pdf')):
  source=pdf.read_bytes(); sha=hashlib.sha256(source).hexdigest()
  git=subprocess.run(['git','show','HEAD:'+str(pdf.relative_to(repository))],cwd=repository,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  assert git.stdout==source, 'Fixture does not match the committed input'
  document=PdfReader(pdf,strict=True)
  assert len(document.pages)==2 and 'TogetherMedia' in document.pages[1].extract_text()
  paper=document.pages[1].mediabox
  for name,exe in renderers.items():
   version=subprocess.run([exe,'-v'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10,check=True)
   version=(version.stdout+version.stderr).decode().splitlines()[0]
   prefix=str(Path(tmp)/(pdf.stem+'-'+name))
   args=[exe,'-f','2','-singlefile','-scale-to','1100','-png',str(pdf),prefix]
   if name=='homebrew-cairo':args[1:1]=['-l','2']
   result=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30,check=True)
   assert not result.stderr, result.stderr.decode()[:200]
   png=Path(prefix+'.png'); image=Image.open(png).convert('RGB')
   factor=image.height/float(paper.height)
   # This fixture's isolated H1 occupies PDF y736...772, above the table/image.
   box=tuple(map(int,(72*factor,(float(paper.height)-772)*factor,450*factor,(float(paper.height)-736)*factor)))
   region=image.crop(box)
   pixels=region.get_flattened_data() if hasattr(region,'get_flattened_data') else region.getdata()
   ink=sum(max(pixel)<160 for pixel in pixels)
   assert ink>200, f'Heading band is blank: {pdf.name}/{name}'
   assert hashlib.sha256(pdf.read_bytes()).hexdigest()==sha
   receipt={'input':str(pdf.relative_to(repository)),'inputSHA256':sha,'reader':name,'version':version,'page':2,'size':list(image.size),'headingDarkPixels':ink,'headingVisible':True,'outputSHA256':hashlib.sha256(png.read_bytes()).hexdigest(),'stderrBytes':0}
   results.append(receipt)
   if pdf.name=='after-table-plain.pdf':
    output=root/(name+'-table-page-2.png');output.write_bytes(png.read_bytes());receipt['savedImage']=output.name
(root/'READER_MATRIX.json').write_text(json.dumps(results,indent=2))
print(json.dumps({'renders':len(results),'passed':True,'fixtureInputs':6,'allHeadingBandsVisible':True},indent=2))
