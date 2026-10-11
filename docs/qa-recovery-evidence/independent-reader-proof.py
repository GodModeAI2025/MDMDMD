#!/usr/bin/env python3
import hashlib, json, os, subprocess, tempfile, time, uuid, zipfile
from pathlib import Path

binary = os.environ['SCRIPTUM_PROCESS_PROOF_BINARY']
with tempfile.TemporaryDirectory(prefix='ScriptumOriginalEvidenceQA-') as scratch:
    root = Path(scratch); source = root / 'Library'; archive = root / 'Evidence.zip'
    subprocess.run([binary, 'bootstrap', str(source)], check=True, capture_output=True, timeout=30)
    (source/'edits').mkdir()
    damaged = source/'edits'/(str(uuid.uuid4()).upper()+'.json')
    damaged.write_bytes(b'not valid JSON\x00\xff\r\n')
    (source/'media/Empty').mkdir(parents=True)
    large = source/'media/Größe-名.bin'
    large.write_bytes(bytes(range(256)) * (8 * 1024 * 1024 // 256) + b'\x00\xffEnd')
    (source/'Recoveries').mkdir()
    (source/'Recoveries/opaque.json').write_bytes(b'broken rescue\xff\x00')
    before = {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in source.rglob('*') if p.is_file() and p.name != '.library.lock'}
    process = subprocess.run([binary, 'evidence', str(source), str(archive)], check=True, capture_output=True, timeout=60)
    receipt = json.loads(process.stdout)
    with zipfile.ZipFile(archive) as zipped:
        assert zipped.testzip() is None
        manifest = json.loads(zipped.read('manifest.json'))
        assert manifest == receipt
        listed = {item['path']: item for item in manifest['files']}
        assert set(listed) == set(before)
        for path, digest in before.items():
            body = zipped.read('Originals/' + path)
            assert body == (source/path).read_bytes()
            assert hashlib.sha256(body).hexdigest() == digest == listed[path]['sha256']
            assert len(body) == listed[path]['bytes']
        assert 'Originals/media/Empty/' in zipped.namelist()
        assert 'Originals/.library.lock' not in zipped.namelist()
        entries = len(zipped.infolist())
    after = {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in source.rglob('*') if p.is_file() and p.name != '.library.lock'}
    assert before == after
    unzip = subprocess.run(['/usr/bin/unzip', '-t', str(archive)], check=True, capture_output=True, timeout=30)
    result = dict(scope='current Core helper, Python ZIP/CRC/SHA reader and macOS unzip; not native iOS sharing',
                  original_files=len(before), original_bytes=sum(x['bytes'] for x in receipt['files']),
                  zip_entries=entries, crc_valid=True, sha256_manifest_valid=True, source_files_unchanged=True,
                  opaque_journals_preserved=True, empty_directory_preserved=True,
                  archive_bytes=archive.stat().st_size, archive_sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
                  unzip_exit_code=unzip.returncode)
    race_source = source/'media/Race64MiB.bin'
    block = bytes(range(256)) * (1024 * 1024 // 256)
    with race_source.open('wb') as output:
        for _ in range(64): output.write(block)
    race_destination = root/'Race.zip'
    child = subprocess.Popen([binary, 'evidence', str(source), str(race_destination)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic()+30
        while not list(root.glob('.scriptum-rescue-*')):
            if child.poll() is not None or time.monotonic() >= deadline: raise RuntimeError('No live stage marker for publication race')
            time.sleep(0.005)
        sentinel = b'Target created after archive staging began'
        with race_destination.open('xb') as output: output.write(sentinel)
        stdout, stderr = child.communicate(timeout=60)
        assert child.returncode == 0, child.returncode
        assert json.loads(stdout) == {'error':'destinationExists'}
        assert race_destination.read_bytes() == sentinel
        assert not list(root.glob('.scriptum-rescue-*'))
        result['late_destination_preserved'] = True
        result['race_export_result'] = 'destinationExists'
    finally:
        if child.poll() is None: child.kill(); child.wait(timeout=30)
        child.stdout.close(); child.stderr.close()
    Path(__file__).with_name('INDEPENDENT_READER_RESULT.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result, indent=2))
