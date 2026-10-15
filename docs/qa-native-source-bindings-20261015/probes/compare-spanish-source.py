from pathlib import Path
import hashlib,json,subprocess,os,zipfile
r=Path(__file__).resolve().parent
source=r/'Spanish-source-tree/resultats/lt/source.tsv';decoded=r/'Spanish-2.3-decoded.tsv';normalized=r/'Spanish-2.3-tagger-semantic.tsv'
cp=(r.parent/'native-quality-aot-20261014/classpath.txt').read_text().strip();jar=Path(next(x for x in cp.split(':') if x.endswith('/spanish-pos-dict-2.3.jar')))
with zipfile.ZipFile(jar) as archive:
 info=archive.read('org/languagetool/resource/es/es-ES.info')
 assert b'fsa.dict.frequency-included=true' in info
with decoded.open('r',encoding='utf-8') as stream, normalized.open('x',encoding='utf-8') as output:
 count=0
 for row in stream:
  word,stem,tag=row.rstrip('\n').split('\t');tag=tag[:-1] if len(tag)>1 else tag
  output.write(word+'\t'+stem+'\t'+tag+'\n');count+=1
outdir=r/'spanish-compare';outdir.mkdir()
config=dict(os.environ);config['LC_ALL']='C'
for name,input_path in [('source',source),('binary',normalized)]:
 subprocess.run(['/usr/bin/sort','-u','-S','64M','-T',str(outdir),'-o',str(outdir/(name+'.tsv')),str(input_path)],check=True,env=config,timeout=120)
def fingerprint(path):
 digest=hashlib.sha256();rows=0;size=0
 with path.open('rb') as stream:
  for chunk in iter(lambda:stream.read(1024*1024),b''):digest.update(chunk);rows+=chunk.count(b'\n');size+=len(chunk)
 return {'sha256':digest.hexdigest(),'rows':rows,'bytes':size}
a=fingerprint(outdir/'source.tsv');b=fingerprint(outdir/'binary.tsv')
report={'repository':'jaumeortola/spanish-dict-tools','commit':'fbeef4f94e18c65daa51867a2aa1b724b423f54b','binaryArtifact':jar.name,'binaryArtifactSHA256':hashlib.sha256(jar.read_bytes()).hexdigest(),'dictionaryMetadataSHA256':hashlib.sha256(info).hexdigest(),'sourceGeneration':'Unmodified pinned Perl noun/adjective/verb generators; upstream comment removal and C-locale deduplication; unmodified sptotabs.pl','comparisonScope':'Complete distinct word/lemma/tag rows, with the metadata-declared frequency suffix removed as LanguageTool 6.6 BaseTagger does; not frequency or binary serialization identity','sourceRows':a,'decodedRows':b,'decodedRawRows':count,'semanticRowsEqual':a==b}
(r/'Spanish-2.3-final-source-proof.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2),flush=True)
if a!=b:raise SystemExit('Spanish source mismatch; do not claim source equivalence')
