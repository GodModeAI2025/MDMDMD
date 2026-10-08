#!/usr/bin/env python3
"""Verify Scriptum's actual signing/PCC gates without printing credentials or profiles."""
import argparse
import datetime
import json
import pathlib
import plistlib
import subprocess


def plist_command(arguments):
    result = subprocess.run(arguments, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return plistlib.loads(result.stdout)


def verify(application, distribution=False):
    application = pathlib.Path(application).resolve(strict=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(application)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    info = plistlib.loads((application / 'Info.plist').read_bytes())
    signature = plist_command(['codesign', '-d', '--entitlements', ':-', str(application)])
    profile = plist_command(['security', 'cms', '-D', '-i', str(application / 'embedded.mobileprovision')])
    expected = 'SP73Z8JWXM.com.mobilebox.Skriptum'
    pcc = 'com.apple.developer.private-cloud-compute'
    checks = {
        'bundle': info.get('CFBundleIdentifier') == 'com.mobilebox.Skriptum',
        'profileApplication': profile['Entitlements'].get('application-identifier') == expected,
        'signatureApplication': signature.get('application-identifier') == expected,
        'team': profile.get('TeamIdentifier') == ['SP73Z8JWXM'],
        'profilePCC': profile['Entitlements'].get(pcc) is True,
        'signaturePCC': signature.get(pcc) is True,
        'runtimeGate': info.get('ScriptumPCCProvisioned') is True,
        'notExpired': profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
        'minimumOS27': str(info.get('MinimumOSVersion', '')).split('.')[0] == '27',
    }
    if distribution:
        checks['distributionSignature'] = signature.get('get-task-allow') is False
        checks['distributionProfile'] = profile['Entitlements'].get('get-task-allow') is False
        checks['appStoreProfile'] = not profile.get('ProvisionedDevices') and not profile.get('ProvisionsAllDevices', False)
        checks['testFlightEligible'] = profile['Entitlements'].get('beta-reports-active') is True
    result = {
        'checks': checks, 'passed': all(checks.values()),
        'version': info.get('CFBundleShortVersionString'), 'build': info.get('CFBundleVersion'),
        'profileUUID': profile.get('UUID'), 'profileName': profile.get('Name'),
        'profileExpiration': profile['ExpirationDate'].isoformat() + 'Z',
        'distributionRequired': distribution,
    }
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('application', type=pathlib.Path, help='Real signed .app inside archive or exported IPA')
    parser.add_argument('--distribution', action='store_true')
    parser.add_argument('--output', type=pathlib.Path)
    args = parser.parse_args()
    try:
        result = verify(args.application, args.distribution)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        # No subprocess stdout/stderr: signing tools can contain private profile fields.
        result = {'passed': False, 'verificationError': type(error).__name__}
    text = json.dumps(result, indent=2) + '\n'
    if args.output:
        args.output.write_text(text)
    print(text, end='')
    raise SystemExit(0 if result['passed'] else 1)


if __name__ == '__main__':
    main()
