import socket,sys,json,pathlib
S=pathlib.Path('/tmp/qpx/mcp.sock')
name=sys.argv[1]; args=json.loads(sys.argv[2]) if len(sys.argv)>2 else {}
c=socket.socket(socket.AF_UNIX); c.connect(str(S))
c.sendall(json.dumps({'name':name,'arguments':args}).encode()+b'\n')
d=b''
while not d.endswith(b'\n'):
    b=c.recv(65536)
    if not b:break
    d+=b
print(d.decode())
