import socket,sys,json,shutil,pathlib
out=pathlib.Path(sys.argv[1]); name=sys.argv[2]; tool=sys.argv[3]; args=json.loads(sys.argv[4]) if len(sys.argv)>4 else {}
c=socket.socket(socket.AF_UNIX); c.connect('/tmp/qpx/mcp.sock')
c.sendall(json.dumps({'name':tool,'arguments':args}).encode()+b'\n')
d=b''
while not d.endswith(b'\n'):
    b=c.recv(1<<20)
    if not b:break
    d+=b
r=json.loads(d)
out.mkdir(parents=True,exist_ok=True)
(out/f'{name}.json').write_text(json.dumps(r,indent=2,ensure_ascii=False))
sc=r.get('result',{}).get('structuredContent',{}) or {}
for k,suf in (('hierarchyPath','hierarchyPath.txt'),('logsPath','logsPath.txt'),('screenshotPath','screenshotPath.png')):
    p=sc.get(k)
    if p and pathlib.Path(p).exists(): shutil.copy(p,out/f'{name}-{suf}')
print(json.dumps({k:v for k,v in sc.items() if 'Path' not in k})[:600], 'ERR' if r.get('result',{}).get('isError') else '')
