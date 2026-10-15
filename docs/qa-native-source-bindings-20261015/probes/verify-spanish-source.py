from pathlib import Path, PurePosixPath
import hashlib,json,subprocess,tarfile
r=Path(__file__).resolve().parent
out=r/'Spanish-source-tree';out.mkdir()
with tarfile.open(r/'Spanish-2.3.tar.gz') as archive:
 for entry in archive:
  path=PurePosixPath(entry.name)
  if path.is_absolute() or '..' in path.parts or '\\' in entry.name:raise ValueError('Unsafe source path')
  target=out.joinpath(*path.parts[1:])
  if entry.isdir():target.mkdir(parents=True,exist_ok=True)
  elif entry.isfile():
   target.parent.mkdir(parents=True,exist_ok=True)
   with target.open('xb') as stream:stream.write(archive.extractfile(entry).read())
  else:raise ValueError('Non-regular source entry')
results=out/'resultats/lt';results.mkdir(parents=True,exist_ok=True)
profile='(version 1)(allow default)(deny network*)(deny file-write*)(allow file-write* (subpath '+json.dumps(str(out))+'))'
commands=[['fdic-to-lt/flexiona.pl','diccionari-arrel/noms-fdic.txt','resultats/lt/noms-lt.txt'],['fdic-to-lt/flexiona.pl','diccionari-arrel/adjectius-fdic.txt','resultats/lt/adjectius-lt.txt'],['fdic-to-lt/conjuga-verbs.pl','diccionari-arrel/verbs-fdic.txt','resultats/lt/verbs-lt.txt','diccionari-arrel/models-verbals/']]
for index,args in enumerate(commands):
 with (out/('generation-'+str(index)+'.log')).open('wb') as log:
  subprocess.run(['/usr/bin/sandbox-exec','-p',profile,'/usr/bin/perl']+args,cwd=out,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=90)
others=[]
for path in sorted((out/'diccionari-arrel').glob('*-lt.txt')):
 for line in path.read_text().splitlines():
  # Upstream build-lt.sh removes comments, trailing spaces and empty lines.
  clean=line.split('#',1)[0].rstrip()
  if clean:others.append(clean)
(results/'others-lt.txt').write_text('\n'.join(others)+'\n')
rows=set()
for path in results.glob('*-lt.txt'):
 for line in path.read_bytes().splitlines():rows.add(line)
raw=b'\n'.join(sorted(rows))+b'\n';(results/'diccionari.txt').write_bytes(raw)
with (results/'diccionari.txt').open('rb') as source,(results/'source.tsv').open('xb') as target:
 subprocess.run(['/usr/bin/sandbox-exec','-p',profile,'/usr/bin/perl','morfologik-lt/sptotabs.pl'],cwd=out,stdin=source,stdout=target,stderr=subprocess.PIPE,check=True,timeout=90)
print(json.dumps({'generatedRows':len(rows),'sourceBytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}),flush=True)
home=r.parent/'native-quality-aot-20261014/graalvm-svm-java17-darwin-m1-gluon-22.1.0.1-Final/Contents/Home';cp=(r.parent/'native-quality-aot-20261014/classpath.txt').read_text().strip();jar=next(x for x in cp.split(':') if x.endswith('/spanish-pos-dict-2.3.jar'))
subprocess.run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(home/'bin/java'),'-Xmx256m','-cp',str(r)+':'+cp,'DumpDictionary',jar,'org/languagetool/resource/es/es-ES.dict',str(r/'Spanish-2.3-decoded.tsv')],check=True,timeout=90)
