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


def metadata_checks(info, signature, profile, distribution=False, now=None, platform='iOS'):
    expected = 'SP73Z8JWXM.com.mobilebox.Skriptum'
    pcc = 'com.apple.developer.private-cloud-compute'
    container = 'iCloud.com.mobilebox.Skriptum'
    cloud_containers = 'com.apple.developer.icloud-container-identifiers'
    cloud_services = 'com.apple.developer.icloud-services'
    cloud_environment = 'com.apple.developer.icloud-container-environment'
    entitlements = profile.get('Entitlements', {})
    is_mac = platform == 'macOS'
    application_key = 'com.apple.application-identifier' if is_mac else 'application-identifier'
    push_key = 'com.apple.developer.aps-environment' if is_mac else 'aps-environment'
    aps = signature.get(push_key)
    allowed_aps = ('production',) if distribution else ('development', 'production')
    allowed_cloud = ('Production',) if distribution else ('Development', 'Production')
    expires = profile.get('ExpirationDate')
    if isinstance(expires, datetime.datetime):
        expires = expires.replace(tzinfo=datetime.timezone.utc) if expires.tzinfo is None else expires.astimezone(datetime.timezone.utc)
    current = now or datetime.datetime.now(datetime.timezone.utc)
    current = current.replace(tzinfo=datetime.timezone.utc) if current.tzinfo is None else current.astimezone(datetime.timezone.utc)
    checks = {
        'bundle': info.get('CFBundleIdentifier') == 'com.mobilebox.Skriptum',
        'profileApplication': entitlements.get(application_key) == expected,
        'signatureApplication': signature.get(application_key) == expected,
        'team': profile.get('TeamIdentifier') == ['SP73Z8JWXM'],
        'profilePCC': entitlements.get(pcc) is True,
        'signaturePCC': signature.get(pcc) is True,
        'runtimeGate': info.get('ScriptumPCCProvisioned') is True,
        'notExpired': isinstance(expires, datetime.datetime) and expires > current,
        'profileCloudContainer': isinstance(entitlements.get(cloud_containers), list) and container in entitlements[cloud_containers],
        'signatureCloudContainer': signature.get(cloud_containers) == [container],
        'profileCloudKit': entitlements.get(cloud_services) == '*' or (isinstance(entitlements.get(cloud_services), list) and 'CloudKit' in entitlements[cloud_services]),
        'signatureCloudKit': signature.get(cloud_services) == ['CloudKit'],
        'signatureCloudEnvironment': signature.get(cloud_environment) in allowed_cloud,
        'profilePush': entitlements.get(push_key) in allowed_aps,
        'signaturePush': aps in allowed_aps,
        'pushEnvironmentMatches': aps in allowed_aps and aps == entitlements.get(push_key),
        'iCloudRuntimeGate': info.get('ScriptumICloudProvisioned') is True,
        'sharingSupported': info.get('CKSharingSupported') is True,
        'minimumOS27': str(info.get('LSMinimumSystemVersion' if is_mac else 'MinimumOSVersion', '')).split('.')[0] == '27',
    }
    if is_mac:
        checks['nativeMacPlatform'] = info.get('CFBundleSupportedPlatforms') == ['MacOSX'] and profile.get('Platform') == ['OSX']
        for key in ('app-sandbox', 'files.user-selected.read-write', 'network.client', 'network.server'):
            checks['mac.' + key] = signature.get('com.apple.security.' + key) is True
    else:
        checks['remoteNotificationBackground'] = isinstance(info.get('UIBackgroundModes'), list) and 'remote-notification' in info['UIBackgroundModes']
    if distribution:
        # Mac App Store profiles normally omit get-task-allow altogether.
        checks['distributionSignature'] = signature.get('com.apple.security.get-task-allow', False) is False if is_mac else signature.get('get-task-allow') is False
        checks['distributionProfile'] = entitlements.get('com.apple.security.get-task-allow', False) is False if is_mac else entitlements.get('get-task-allow') is False
        checks['appStoreProfile'] = not profile.get('ProvisionedDevices') and not profile.get('ProvisionsAllDevices', False)
        if not is_mac:
            checks['testFlightEligible'] = entitlements.get('beta-reports-active') is True
    return checks


def verify(application, distribution=False):
    application = pathlib.Path(application).resolve(strict=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(application)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    is_mac = (application / 'Contents/Info.plist').is_file()
    content = application / 'Contents' if is_mac else application
    info = plistlib.loads((content / 'Info.plist').read_bytes())
    signature = plist_command(['codesign', '-d', '--xml', '--entitlements', '-', str(application)])
    profile = plist_command(['security', 'cms', '-D', '-i', str(content / ('embedded.provisionprofile' if is_mac else 'embedded.mobileprovision'))])
    platform = 'macOS' if is_mac else 'iOS'
    checks = metadata_checks(info, signature, profile, distribution, platform=platform)
    if distribution:
        signing = subprocess.run(['codesign', '-dvv', str(application)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stderr.decode()
        checks['distributionCertificate'] = any(line.startswith(('Authority=Apple Distribution:', 'Authority=3rd Party Mac Developer Application:')) for line in signing.splitlines())
    result = {
        'checks': checks, 'passed': all(checks.values()),
        'version': info.get('CFBundleShortVersionString'), 'build': info.get('CFBundleVersion'),
        'profileUUID': profile.get('UUID'), 'profileName': profile.get('Name'),
        'profileExpiration': profile['ExpirationDate'].isoformat() + 'Z',
        'distributionRequired': distribution, 'platform': platform,
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
