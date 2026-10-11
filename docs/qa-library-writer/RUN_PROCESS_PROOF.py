from pathlib import Path
import subprocess,json,tempfile,os,signal,hashlib
binary=Path(os.environ.get('SCRIPTUM_LIBRARY_PROOF_EXECUTABLE', '/private/tmp/SkriptumLibraryProcessProof/debug/LibraryProcessProof'))
assert binary.is_file(),binary
children=[]
def run(args):
 p=subprocess.run([str(binary),*map(str,args)],capture_output=True,text=True,check=True)
 return json.loads(p.stdout.strip())
def start(args):
 p=subprocess.Popen([str(binary),*map(str,args)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 children.append(p)
 return p
with tempfile.TemporaryDirectory(prefix='ScriptumLibraryProcessQA-') as temp:
 root=Path(temp);library=root/'Library';run(['bootstrap',library])
 trials=[]
 try:
  for i in range(20):
   a=start(['writer',library,f'Writer-{i}-A']);assert json.loads(a.stdout.readline())['state']=='ready'
   b=start(['writer',library,f'Writer-{i}-B']);assert json.loads(b.stdout.readline())['state']=='ready'
   for p in [a,b]:p.stdin.write('GO\n');p.stdin.flush()
   states=[json.loads(p.stdout.readline())['state'] for p in [a,b]]
   for p in [a,b]:assert p.wait()==0,p.stderr.read()
   assert sorted(states)==['committed','conflict'],states
   inspected=root/'inspect.json';run(['inspect',library,inspected]);snapshot=json.loads(inspected.read_text())
   assert len(snapshot['spaces'])==i+2
   trials.append({'trial':i+1,'states':states,'durableSpaceCount':len(snapshot['spaces'])})
  source=('Recovered 🦊 e\u0301\r\n\r\n'+('Long draft with exact Unicode 🦊 and CRLF.\r\n'*8000)).encode()
  src=root/'source.md';src.write_bytes(source)
  draft=start(['draft',library,src]);assert json.loads(draft.stdout.readline())['state']=='journaled'
  # Kill only this exact child created above, after its durable journal receipt.
  os.kill(draft.pid,signal.SIGKILL);assert draft.wait()==-signal.SIGKILL
  recovered=root/'recovered.json';run(['inspect',library,recovered]);snapshot=json.loads(recovered.read_text())
  actual=''.join(b['markdown'] for b in snapshot['pages'][0]['blocks']).encode()
  assert actual==source
  assert len(snapshot['revisions'])==1
  baseline=''.join(b['markdown'] for b in snapshot['revisions'][0]['page']['blocks']).encode()
  assert baseline==b'Original\r\n'
  assert len(snapshot['spaces'])==21
  assert not list((library/'edits').glob('*.json'))
  receipt={'twentyTwoProcessTrials':trials,'actualDraftProcessKilledAfterJournalWrite':True,'draftBytes':len(source),'draftSHA256':hashlib.sha256(source).hexdigest(),'recoveredSHA256':hashlib.sha256(actual).hexdigest(),'exactUTF8AndCRLFPreserved':True,'baselineRevisionPreserved':True,'allPriorSpacesPreserved':21,'journalsConsumedAfterRecovery':True,'physicalIOSDeviceVerified':False}
  Path(__file__).with_name('PROCESS_PROOF_LATEST.json').write_text(json.dumps(receipt,indent=2));print(json.dumps({k:v for k,v in receipt.items() if k!='twentyTwoProcessTrials'}))
 finally:
  for p in children:
   if p.poll() is None:
    p.stdin.close();p.terminate();p.wait()
