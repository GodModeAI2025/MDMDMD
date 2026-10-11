#!/usr/bin/env python3
"""Bounded synthetic compressed-change decoding; Darwin host only.
Never run arbitrary user fixtures. Child CPU=3s, wall=5s, observed RSS=192MiB.
Fixture expansion maximum=64MiB; streamed generation avoids large parent allocations.
"""
import argparse, json, os, pathlib, resource, signal, subprocess, sys, tempfile, time, zlib


def uleb(value):
    out = bytearray()
    while value >= 128:
        out.append((value & 127) | 128); value >>= 7
    out.append(value); return bytes(out)


def fixture(path, megabytes):
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    data = bytearray()
    for _ in range(megabytes):
        data.extend(compressor.compress(bytes(1024 * 1024)))
    data.extend(compressor.flush())
    # Upstream storage/chunk.rs: magic, 4 checksum bytes, type2,
    # compressed byte length as unsigned LEB128, raw DEFLATE payload.
    # Deliberately malformed change/checksum: load parses/inflates before
    # checksum validation. This is NOT a dependency artifact checksum override.
    path.write_bytes(bytes.fromhex('856f4a83') + bytes(4) + bytes([2]) + uleb(len(data)) + data)
    return path.stat().st_size


def child_limits():
    resource.setrlimit(resource.RLIMIT_CPU, (3, 3))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def run(binary, path):
    with tempfile.TemporaryFile() as output:
        proc = subprocess.Popen([binary, str(path)], stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT, preexec_fn=child_limits, start_new_session=True)
        start = time.monotonic(); observed = 0; stopped = None
        while True:
            pid, status, usage = os.wait4(proc.pid, os.WNOHANG)
            if pid:
                proc.returncode = os.waitstatus_to_exitcode(status); break
            try:
                rss = subprocess.run(['/bin/ps', '-o', 'rss=', '-p', str(proc.pid)], capture_output=True, text=True).stdout.strip()
            except BaseException:
                # Do not leave a decoder running if monitor setup is denied.
                os.killpg(proc.pid, signal.SIGKILL)
                _, status, _ = os.wait4(proc.pid, 0)
                proc.returncode = os.waitstatus_to_exitcode(status)
                raise
            if rss.isdigit(): observed = max(observed, int(rss) * 1024)
            if stopped is None and (observed > 192 * 1024 * 1024 or time.monotonic() - start > 5):
                stopped = 'rss' if observed > 192 * 1024 * 1024 else 'wall'
                os.killpg(proc.pid, signal.SIGKILL)
            time.sleep(0.005)
        output.seek(0)
        return dict(exit=proc.returncode, stopped=stopped, seconds=round(time.monotonic()-start, 4), observedRSSBytes=observed, kernelPeakRSSBytes=usage.ru_maxrss, cpuSeconds=round(usage.ru_utime+usage.ru_stime,4), output=output.read(4096).decode(errors='replace'))


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('binary'); args = parser.parse_args()
    if sys.platform != 'darwin': raise SystemExit('Darwin-only RSS units and process monitor')
    with tempfile.TemporaryDirectory(prefix='scriptum-parser-probe-') as directory:
        for size in [0, 1, 16, 64]:
            path = pathlib.Path(directory)/f'{size}.bin'
            compressed = fixture(path, size)
            result = run(args.binary, path)
            print(json.dumps(dict(inflatedMiB=size, inputBytes=compressed, **result)), flush=True)
            if result['stopped']: break

if __name__ == '__main__': main()
