#!/usr/bin/env python3
"""SIGKILL only this harness's child, then verify source-only recovery in a new process."""
import hashlib, json, os, select, signal, subprocess, tempfile
from pathlib import Path

binary = os.environ['SCRIPTUM_PROCESS_PROOF_BINARY']
receipt_path = Path(__file__).with_name('PROCESS_RESULT.json')
with tempfile.TemporaryDirectory(prefix='ScriptumPartialRecoveryQA-') as scratch:
    root = Path(scratch)
    source = ('# Entwurf\r\n' + ('Cafe\u0301 – 🦊 日本語\r\n' * 8000)).encode('utf-8')
    original = root / 'source.md'
    original.write_bytes(source)
    restored = root / 'readback.md'
    child = subprocess.Popen([binary, 'partial-recovery', str(root / 'Library'), str(original)],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        if not select.select([child.stdout], [], [], 30)[0]:
            raise RuntimeError('Child did not publish a recovery receipt within 30 seconds')
        captured = json.loads(child.stdout.readline())
        assert captured['state'] == 'source-only', captured
        child.send_signal(signal.SIGKILL)
        return_code = child.wait(timeout=30)
        assert return_code == -signal.SIGKILL, return_code
        inspection = subprocess.run([binary, 'inspect-partial', str(root / 'Library'), str(restored)],
                                    capture_output=True, check=True, timeout=30, text=True)
        reopened = json.loads(inspection.stdout)
        assert reopened['state'] == 'inspected-partial', reopened
        assert reopened['id'] == captured['id'], (captured, reopened)
        assert restored.read_bytes() == source
        receipt = dict(scope='macOS Core helper; independent post-SIGKILL process; not iOS or power-loss proof',
                       source_bytes=len(source), sha256=hashlib.sha256(source).hexdigest(),
                       child_exit_code=return_code, captured=captured, reopened=reopened,
                       byte_equal=True, completeness='sourceOnly')
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps(receipt, indent=2))
    finally:
        if child.poll() is None:
            child.kill()
            child.wait(timeout=30)
        for stream in (child.stdin, child.stdout, child.stderr):
            stream.close()
