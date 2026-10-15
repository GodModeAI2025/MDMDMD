from pathlib import Path, PurePosixPath
import concurrent.futures, hashlib, json, posixpath, tarfile, urllib.request
ROOT=Path(__file__).resolve().parent
SPECS=[('johanvos/mobile','65db66f6d9c46c4bd0eaea87ac6ff3e035d43d49','OpenJDK-mobile-prep18-9'),('jaumeortola/spanish-dict-tools','fbeef4f94e18c65daa51867a2aa1b724b423f54b','Spanish-2.3'),('languagetool-org/french-pos-dict','ff11b571918809d8ae39669a9c815c71c1d9fb6c','French-0.7')]
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs): raise ValueError('Unexpected redirect')
opener=urllib.request.build_opener(NoRedirect)
def get(url,maximum,destination):
 request=urllib.request.Request(url,headers={'User-Agent':'Scriptum-source-materials/1','Accept':'application/vnd.github+json' if url.startswith('https://api.github.com/') else 'application/octet-stream'})
 count=0
 with opener.open(request,timeout=60) as response, destination.open('xb') as output:
  if response.status!=200:raise ValueError('Unexpected status')
  while True:
   chunk=response.read(1024*1024)
   if not chunk:break
   count+=len(chunk)
   if count>maximum:raise ValueError('Archive exceeds size limit')
   output.write(chunk)
 return count
def run(spec):
 repo,commit,name=spec
 metadata=ROOT/(name+'-commit.json'); archive=ROOT/(name+'.tar.gz')
 get('https://api.github.com/repos/'+repo+'/git/commits/'+commit,4*1024*1024,metadata)
 if json.loads(metadata.read_text())['sha']!=commit:raise ValueError('Commit mismatch')
 url='https://codeload.github.com/'+repo+'/tar.gz/'+commit
 size=get(url,300*1024*1024,archive)
 prefix=repo.split('/')[1]+'-'+commit
 entries=[];expanded=0
 with tarfile.open(archive,'r:gz') as source:
  for entry in source:
   path=PurePosixPath(entry.name)
   if path.is_absolute() or '..' in path.parts or '\\' in entry.name or path.parts[0]!=prefix:raise ValueError('Unsafe archive entry')
   if entry.isdev() or entry.isfifo():raise ValueError('Special file in source archive')
   if entry.issym():
    target=posixpath.normpath(posixpath.join(posixpath.dirname(entry.name),entry.linkname))
    if target!=prefix and not target.startswith(prefix+'/'):raise ValueError('Escaping source link')
   if entry.islnk():
    target=posixpath.normpath(entry.linkname)
    if not target.startswith(prefix+'/'):raise ValueError('Escaping hard link')
   expanded+=entry.size
   if expanded>2*1024**3 or len(entries)>200000:raise ValueError('Expanded source bound exceeded')
   entries.append({'path':entry.name,'bytes':entry.size,'type':entry.type.decode('ascii')})
 receipt={'repository':repo,'commit':commit,'archive':archive.name,'url':url,'bytes':size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'expandedBytes':expanded,'entries':len(entries)}
 (ROOT/(name+'-receipt.json')).write_text(json.dumps(receipt,indent=2)+'\n')
 (ROOT/(name+'-entries.json')).write_text(json.dumps(entries,indent=2)+'\n')
 print(json.dumps(receipt),flush=True)
 return receipt
if __name__ == "__main__":
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
  for result in executor.map(run,SPECS):pass
