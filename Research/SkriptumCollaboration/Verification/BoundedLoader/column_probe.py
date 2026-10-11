#!/usr/bin/env python3
"""Exact pinned format negative fixtures in the bounded child monitor.
Known expansion paths only; NOT a complete format fuzzer or production guard.
"""
import importlib.util, json, pathlib, sys, tempfile, zlib
spec=importlib.util.spec_from_file_location('monitor', pathlib.Path(__file__).resolve().parents[1]/'ParserProbe'/'run_probe.py')
monitor=importlib.util.module_from_spec(spec); spec.loader.exec_module(monitor)

def deflate(mib):
    z=zlib.compressobj(9,zlib.DEFLATED,-15); out=bytearray()
    for _ in range(mib): out.extend(z.compress(bytes(1024*1024)))
    out.extend(z.flush()); return bytes(out)

def chunk(kind, body):
    return bytes.fromhex('856f4a83')+bytes(4)+bytes([kind])+monitor.uleb(len(body))+body

def document(changes, ops):
    a=deflate(changes) if changes else b''; b=deflate(ops) if ops else b''
    # Type0: actors,heads,change-column metadata,op-column metadata,
    # change column bytes,op column bytes,empty head-index suffix.
    def meta(data): return bytes([1,8])+monitor.uleb(len(data)) if data else bytes([0])
    return chunk(0,bytes([0,0])+meta(a)+meta(b)+a+b)

with tempfile.TemporaryDirectory(prefix='scriptum-column-probe-') as directory:
    cases={'internal-change-column-64MiB':document(64,0),'internal-op-column-64MiB':document(0,64),'aggregate-columns-18MiB':document(9,9),'actor-count-plus-one':chunk(0,monitor.uleb(100_001)), 'head-count-plus-one':chunk(0,bytes([0])+monitor.uleb(100_001)), 'column-count-plus-one':chunk(0,bytes([0,0])+monitor.uleb(100_001)), 'change-dependency-count-plus-one':chunk(1,monitor.uleb(100_001)), 'bundle-dependency-count-plus-one':chunk(3,monitor.uleb(100_001)), 'bundle-actor-count-plus-one':chunk(3,bytes([0])+monitor.uleb(100_001))}
    for name,data in cases.items():
        path=pathlib.Path(directory)/name; path.write_bytes(data)
        result=monitor.run(sys.argv[1],path)
        print(json.dumps(dict(case=name,inputBytes=len(data),**result)),flush=True)
        assert result['exit']==0 and result['stopped'] is None
        assert 'resource budget exceeded' in result['output']
        assert result['kernelPeakRSSBytes'] < 96*1024*1024
