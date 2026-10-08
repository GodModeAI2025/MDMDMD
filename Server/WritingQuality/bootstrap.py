#!/usr/bin/env python3
"""Install pinned rule engine/JRE into an explicit task directory; no global install."""
import argparse, hashlib, pathlib, subprocess, urllib.request
p=argparse.ArgumentParser();p.add_argument('--work-directory',required=True);a=p.parse_args()
root=pathlib.Path(a.work_directory).resolve();root.mkdir(parents=True,exist_ok=True)
assets=[('LanguageTool-6.6.zip','https://languagetool.org/download/LanguageTool-6.6.zip','53600506b399bb5ffe1e4c8dec794fd378212f14aaf38ccef9b6f89314d11631'),('temurin21-jre.tar.gz','https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jre_aarch64_mac_hotspot_21.0.12.1_1.tar.gz','dec50fc6f9fcd4fe3ae8cabf5a5fa68f6afc48841f7698e468e9aa5d54beed84')]
for name,url,expected in assets:
 path=root/name
 if not path.exists():
  with urllib.request.urlopen(url,timeout=180) as response, path.open('wb') as output:
   while chunk:=response.read(1024*1024): output.write(chunk)
 actual=hashlib.sha256(path.read_bytes()).hexdigest()
 if actual!=expected: raise SystemExit('Checksum mismatch: '+name)
 print(name,actual,'VERIFIED')
# Extract only after verification, using pinned archive tools. No executing download scripts.
runtime=root/'writing-quality-runtime';runtime.mkdir(exist_ok=True)
if not (runtime/'LanguageTool-6.6').exists(): subprocess.run(['unzip','-q',str(root/'LanguageTool-6.6.zip'),'-d',str(runtime)],check=True)
if not (runtime/'jdk-21.0.12.1+1-jre').exists(): subprocess.run(['tar','-xzf',str(root/'temurin21-jre.tar.gz'),'-C',str(runtime)],check=True)
print('Start locally:',runtime/'jdk-21.0.12.1+1-jre/Contents/Home/bin/java','-cp',runtime/'LanguageTool-6.6/languagetool-server.jar','org.languagetool.server.HTTPServer --port 8097')
