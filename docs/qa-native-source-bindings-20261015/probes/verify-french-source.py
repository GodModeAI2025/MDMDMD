from pathlib import Path
import hashlib,json,re,tarfile,zipfile
r=Path(__file__).resolve().parent
cp=(r.parent/'native-quality-aot-20261014/classpath.txt').read_text().strip()
jar=Path(next(x for x in cp.split(':') if x.endswith('/french-pos-dict-0.7.jar')))
with zipfile.ZipFile(jar) as archive:
 metadata=archive.read('org/languagetool/resource/fr/french.info')
 assert b'fsa.dict.frequency-included=true' in metadata
with tarfile.open(r/'French-0.7.tar.gz') as archive:
 prefix=archive.getmembers()[0].name.split('/')[0]
 paths=['data/src-dict/dict.txt','lt-changes/added.txt','lt-changes/removed.txt','pos_tagger_scripts/build-lt.sh','pos_tagger_scripts/SuppressionDoublons.sh']
 raw={p:archive.extractfile(prefix+'/'+p).read() for p in paths}
 removed=set(raw['lt-changes/removed.txt'].decode().splitlines())
 preferred=[x for x in raw['data/src-dict/dict.txt'].decode().splitlines() if x not in removed]+[x for x in raw['lt-changes/added.txt'].decode().splitlines() if '#' not in x]
 assembled=set(re.sub(r'^(.*(?:é|ée|és|ées)\t.*)er\t(J .*)$',r'\1é\t\2',x) for x in preferred if x)
actual=set()
for line in (r/'French-0.7-decoded.tsv').read_text().splitlines():
 word,stem,tag=line.split('\t');actual.add('\t'.join([word,stem,tag[:-1] if len(tag)>1 else tag]))
report={'repository':'languagetool-org/french-pos-dict','commit':'ff11b571918809d8ae39669a9c815c71c1d9fb6c','binaryArtifact':jar.name,'binaryArtifactSHA256':hashlib.sha256(jar.read_bytes()).hexdigest(),'dictionaryMetadataSHA256':hashlib.sha256(metadata).hexdigest(),'sourceInputSHA256':{p:hashlib.sha256(v).hexdigest() for p,v in raw.items()},'sourceAssembly':'Upstream build-lt.sh steps 4-7: exact removed rows excluded; added rows without # included; participle/adjective lemma substitution; empty initial row omitted; exact deduplication.','frequencyScope':'Tagger-equivalent comparison removes the declared final frequency byte as LanguageTool 6.6 BaseTagger does. Frequency values and binary serialization are not asserted equal.','sourceRows':len(assembled),'binaryRows':len(actual),'sourceMissingFromBinary':len(assembled-actual),'binaryMissingFromSource':len(actual-assembled),'semanticRowsEqual':assembled==actual,'semanticSourceSHA256':hashlib.sha256(('\n'.join(sorted(assembled))+'\n').encode()).hexdigest()}
assert report['semanticRowsEqual'] and len(actual)>600000
(r/'French-0.7-final-source-proof.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
print(json.dumps({'sourceRows':len(assembled),'binaryRows':len(actual),'equal':assembled==actual}),flush=True)
