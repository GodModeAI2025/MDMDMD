#!/usr/bin/env python3
"""Verify Scriptum's actual signing, PCC and iCloud gates without printing credentials or profiles."""
import argparse
import datetime
import json
import pathlib
import plistlib
import subprocess


def plist_command(arguments):
    result = subprocess.run(arguments, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return plistlib.loads(result.stdout)


def metadata_checks(info, signature, profile, distribution=False, now=None):
    expected = 'SP73Z8JWXM.com.mobilebox.Skriptum'
    pcc = 'com.apple.developer.private-cloud-compute'
    container = 'iCloud.com.mobilebox.Skriptum'
    cloud_containers = 'com.apple.developer.icloud-container-identifiers'
    cloud_services = 'com.apple.developer.icloud-services'
    cloud_environment = 'com.apple.developer.icloud-container-environment'
    entitlements = profile.get('Entitlements', {})
    aps = signature.get('aps-environment')
    allowed_aps = ('production',) if distribution else ('development', 'production')
    allowed_cloud = ('Production',) if distribution else ('Development', 'Production')
    expires = profile.get('ExpirationDate')
    if isinstance(expires, datetime.datetime):
        expires = expires.replace(tzinfo=datetime.timezone.utc) if expires.tzinfo is None else expires.astimezone(datetime.timezone.utc)
    current = now or datetime.datetime.now(datetime.timezone.utc)
    current = current.replace(tzinfo=datetime.timezone.utc) if current.tzinfo is None else current.astimezone(datetime.timezone.utc)
    checks = {
        'bundle': info.get('CFBundleIdentifier') == 'com.mobilebox.Skriptum',
        'profileApplication': entitlements.get('application-identifier') == expected,
        'signatureApplication': signature.get('application-identifier') == expected,
        'team': profile.get('TeamIdentifier') == ['SP73Z8JWXM'],
        'profilePCC': entitlements.get(pcc) is True,
        'signaturePCC': signature.get(pcc) is True,
        'runtimeGate': info.get('ScriptumPCCProvisioned') is True,
        'notExpired': isinstance(expires, datetime.datetime) and expires > current,
        'profileCloudContainer': isinstance(entitlements.get(cloud_containers), list) and container in entitlements[cloud_containers],
        'signatureCloudContainer': signature.get(cloud_containers) == [container],
        'profileCloudKit': isinstance(entitlements.get(cloud_services), list) and 'CloudKit' in entitlements[cloud_services],
        'signatureCloudKit': signature.get(cloud_services) == ['CloudKit'],
        'signatureCloudEnvironment': signature.get(cloud_environment) in allowed_cloud,
        'profilePush': entitlements.get('aps-environment') in allowed_aps,
        'signaturePush': aps in allowed_aps,
        'pushEnvironmentMatches': aps in allowed_aps and aps == entitlements.get('aps-environment'),
        'iCloudRuntimeGate': info.get('ScriptumICloudProvisioned') is True,
        'sharingSupported': info.get('CKSharingSupported') is True,
        'remoteNotificationBackground': isinstance(info.get('UIBackgroundModes'), list) and 'remote-notification' in info['UIBackgroundModes'],
        'minimumOS27': str(info.get('MinimumOSVersion', '')).split('.')[0] == '27',
    }
    if distribution:
        checks['distributionSignature'] = signature.get('get-task-allow') is False
        checks['distributionProfile'] = entitlements.get('get-task-allow') is False
        checks['appStoreProfile'] = not profile.get('ProvisionedDevices') and not profile.get('ProvisionsAllDevices', False)
        checks['testFlightEligible'] = entitlements.get('beta-reports-active') is True
    return checks


def verify(application, distribution=False):
    application = pathlib.Path(application).resolve(strict=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(application)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    info = plistlib.loads((application / 'Info.plist').read_bytes())
    signature = plist_command(['codesign', '-d', '--entitlements', ':-', str(application)])
    profile = plist_command(['security', 'cms', '-D', '-i', str(application / 'embedded.mobileprovision')])
    checks = metadata_checks(info, signature, profile, distribution)
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
    except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.CalledProcessError) as error:
        # No subprocess stdout/stderr: signing tools can contain private profile fields.
        result = {'passed': False, 'verificationError': type(error).__name__}
    text = json.dumps(result, indent=2) + '\n'
    if args.output:
        args.output.write_text(text)
    print(text, end='')
    raise SystemExit(0 if result['passed'] else 1)


if __name__ == '__main__':
    main()
