from pathlib import Path
import hashlib,importlib.util,json,subprocess,time
r=Path(__file__).resolve().parent;w=r.parent
repo=w.parent/'outputs/Skriptum'
framework=w/'native-quality-distribution-20261015/frameworks-final/macos/ScriptumGrammar.framework/ScriptumGrammar'
resources=w/'native-quality-distribution-20261015/frameworks-final/ScriptumGrammarResources.bundle'
runner=w/'native-quality-distribution-20261015/framework-verified/NativeCorpusRunner'
java=w/'native-quality-aot-20261014/graalvm-svm-java17-darwin-m1-gluon-22.1.0.1-Final/Contents/Home/bin/java'
cp=str(w/'native-quality-worker-20261015/java-target/classes')+':'+(w/'native-quality-aot-20261014/classpath.txt').read_text().strip()
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(r/'FrozenCorpus.json')=='520a104fd28d9fd0de12f9e528ed2c767c58ca046a7884720d18ead11f4f9c36'
assert sha(framework)=='99437b77affb8b23e50adbaba940d2beef7a27e9205f0d6948b82982e8905f79'
assert sha(resources/'manifest.json')=='2ddd9b3c07bee931ae6474bbded3774a1475c9fff8ff2178d8541a1cf32be526'
spec=importlib.util.spec_from_file_location('frameworks',repo/'Research/NativeWritingQuality/build_frameworks.py'); module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
records=module.resource_records(resources.resolve(),json.loads((resources/'manifest.json').read_text()))
network=['/usr/bin/time','-l','/usr/bin/sandbox-exec','-p','(version 1) (allow default) (deny network*)']
commands={
'jvm':network+[str(java),'-Xmx1536m','-Dscriptum.resources.root='+str(resources),'-cp',cp,'com.mobilebox.research.NativeWritingQuality','--corpus',str(r/'EngineInputs.json')],
'native':network+[str(runner),str(r/'EngineInputs.json'),'--isolate-per-record','--heap-mb=256','--resource-root='+str(resources)]}
(r/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
state={'corpusSHA256':sha(r/'FrozenCorpus.json'),'inputsSHA256':sha(r/'EngineInputs.json'),'frameworkSHA256':sha(framework),'runnerSHA256':sha(runner),'verifiedResources':len(records),'network':'denied by sandbox-exec','runs':{},'scope':'Raw native/JVM execution, no language-quality pass inferred from exit code'}
for name,command in commands.items():
 start=time.monotonic()
 with (r/(name+'-responses.json')).open('xb') as out,(r/(name+'.stderr')).open('xb') as err:
  run=subprocess.run(command,stdout=out,stderr=err)
 state['runs'][name]={'exitCode':run.returncode,'elapsedSeconds':round(time.monotonic()-start,3),'responseSHA256':sha(r/(name+'-responses.json'))}
 (r/'EXECUTION.json').write_text(json.dumps(state,indent=2)+'\n')
 print(name,state['runs'][name],flush=True)
 if run.returncode:raise SystemExit(run.returncode)
