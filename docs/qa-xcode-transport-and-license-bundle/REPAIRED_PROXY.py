import subprocess,json,socket,os,select,time,pathlib
root=pathlib.Path(__file__).resolve().parent
path=root/'mcp.sock'
if path.exists(): raise RuntimeError('Existing socket requires owner cleanup')
p=subprocess.Popen(['xcrun','mcpbridge'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,bufsize=0)
counter=0
buffer=b''
def send(value):
 p.stdin.write((json.dumps(value)+'\n').encode());p.stdin.flush()
def rpc(method,params):
 global counter,buffer
 counter+=1
 send({'jsonrpc':'2.0','id':counter,'method':method,'params':params})
 deadline=time.monotonic()+180
 while time.monotonic()<deadline:
  while b'\n' in buffer:
   line,buffer=buffer.split(b'\n',1)
   if not line.strip():continue
   result=json.loads(line)
   with (root/'frames.jsonl').open('a') as trace:
    trace.write(json.dumps({'id':result.get('id'),'method':result.get('method'),'bytes':len(line)})+'\n')
   if result.get('id')==counter:return result
  remaining=deadline-time.monotonic()
  if remaining<=0:break
  if select.select([p.stdout],[],[],min(1,remaining))[0]:
   chunk=os.read(p.stdout.fileno(),65536)
   if not chunk:raise RuntimeError('Bridge exited')
   buffer+=chunk
   if len(buffer)>64*1024*1024:raise RuntimeError('MCP frame exceeds diagnostic limit')
 raise RuntimeError('MCP timeout; no automatic retry')
server=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
try:
 rpc('initialize',{'protocolVersion':'2024-11-05','capabilities':{},'clientInfo':{'name':'NativePickerOwnedProxy','version':'1'}})
 send({'jsonrpc':'2.0','method':'notifications/initialized'})
 server.bind(str(path));os.chmod(path,0o600);server.listen(1)
 print(json.dumps({'ready':True,'socket':str(path),'bridgePID':p.pid}),flush=True)
 running=True
 while running:
  conn,_=server.accept()
  with conn:
   data=b''
   while b'\n' not in data:
    block=conn.recv(4096)
    if not block:break
    data+=block
    if len(data)>65536:raise RuntimeError('Request too large')
   try:
    req=json.loads(data)
    if req=={'shutdown':True}:result={'shutdown':True};running=False
    else:
     if set(req)!={'name','arguments'}:raise ValueError('Only exact tool request supported')
     result=rpc('tools/call',req)
    with (root/'proxy-receipts.jsonl').open('a') as out:out.write(json.dumps({'request':req,'result':result})+'\n')
   except Exception as e:result={'error':str(e)}
   conn.sendall(json.dumps(result).encode()+b'\n')
finally:
 server.close();p.terminate()
 try:p.wait(timeout=5)
 except subprocess.TimeoutExpired:p.kill();p.wait()
 if path.exists():path.unlink()
