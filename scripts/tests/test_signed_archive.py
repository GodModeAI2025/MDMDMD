import copy
import datetime
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('verifier', Path(__file__).parents[1] / 'verify_signed_archive.py')
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)

class SignedArchiveCloudGates(unittest.TestCase):
    def setUp(self):
        self.now = datetime.datetime(2026, 10, 11, tzinfo=datetime.timezone.utc)
        self.info = {'CFBundleIdentifier': 'com.mobilebox.Skriptum', 'MinimumOSVersion':'27.0', 'ScriptumPCCProvisioned':True, 'ScriptumICloudProvisioned':True, 'CKSharingSupported':True, 'UIBackgroundModes':['processing','remote-notification']}
        self.signature = {'application-identifier':'SP73Z8JWXM.com.mobilebox.Skriptum', 'com.apple.developer.private-cloud-compute':True, 'com.apple.developer.icloud-container-identifiers':['iCloud.com.mobilebox.Skriptum'], 'com.apple.developer.icloud-services':['CloudKit'], 'com.apple.developer.icloud-container-environment':'Production', 'aps-environment':'production', 'get-task-allow':False}
        self.profile = {'TeamIdentifier':['SP73Z8JWXM'], 'ExpirationDate':datetime.datetime(2027,10,11), 'Entitlements':copy.deepcopy(self.signature)}
        self.profile['Entitlements']['beta-reports-active']=True
    def checks(self, distribution=True):
        return verifier.metadata_checks(self.info,self.signature,self.profile,distribution,self.now)
    def test_valid_distribution_metadata(self):
        self.assertTrue(all(self.checks().values()))
    def test_old_pcc_only_profile_is_rejected(self):
        for target in (self.signature,self.profile['Entitlements']):
            for key in tuple(target):
                if 'icloud' in key or key=='aps-environment': target.pop(key)
        self.info.pop('ScriptumICloudProvisioned')
        checks=self.checks()
        self.assertTrue(checks['profilePCC'] and checks['signaturePCC'])
        self.assertFalse(all(checks.values()))
        self.assertFalse(checks['profileCloudContainer'])
        self.assertFalse(checks['iCloudRuntimeGate'])
    def test_another_or_extra_container_is_rejected(self):
        key='com.apple.developer.icloud-container-identifiers'
        for value in (['iCloud.Other'],['iCloud.com.mobilebox.Skriptum','iCloud.Other'],'iCloud.com.mobilebox.Skriptum'):
            self.signature[key]=value
            self.assertFalse(self.checks()['signatureCloudContainer'])
    def test_profile_cannot_authorize_a_different_container(self):
        self.profile['Entitlements']['com.apple.developer.icloud-container-identifiers']=['iCloud.Other']
        self.assertFalse(self.checks()['profileCloudContainer'])
    def test_cloud_documents_is_not_cloudkit(self):
        self.signature['com.apple.developer.icloud-services']=['CloudDocuments']
        self.assertFalse(self.checks()['signatureCloudKit'])
    def test_apple_wildcard_service_profile_authorizes_cloudkit_but_not_the_signature(self):
        self.profile['Entitlements']['com.apple.developer.icloud-services']='*'
        self.assertTrue(self.checks()['profileCloudKit'])
        self.signature['com.apple.developer.icloud-services']='*'
        self.assertFalse(self.checks()['signatureCloudKit'])
    def test_push_environments_must_match(self):
        self.profile['Entitlements']['aps-environment']='development'
        self.assertFalse(self.checks(False)['pushEnvironmentMatches'])
    def test_development_is_not_distribution(self):
        for target in (self.signature,self.profile['Entitlements']): target['aps-environment']='development'
        self.signature['com.apple.developer.icloud-container-environment']='Development'
        self.assertFalse(all(self.checks(True).values()))
        self.assertTrue(all(self.checks(False).values()))
    def test_runtime_flags_cannot_be_truthy_strings(self):
        self.info['ScriptumICloudProvisioned']='true'
        self.assertFalse(self.checks()['iCloudRuntimeGate'])
    def test_expired_and_malformed_dates_fail_closed(self):
        for expiry in (self.now,self.now-datetime.timedelta(seconds=1),None,'tomorrow'):
            self.profile['ExpirationDate']=expiry
            self.assertFalse(self.checks()['notExpired'])
    def test_sharing_and_background_support_are_required(self):
        self.info.pop('CKSharingSupported')
        self.info['UIBackgroundModes']=['processing']
        self.assertFalse(self.checks()['sharingSupported'])
        self.assertFalse(self.checks()['remoteNotificationBackground'])

class NativeMacDistributionGates(unittest.TestCase):
    setUp = SignedArchiveCloudGates.setUp
    def mac_checks(self):
        info = copy.deepcopy(self.info)
        info.pop('MinimumOSVersion', None)
        info.pop('UIBackgroundModes', None)
        info.update(LSMinimumSystemVersion='27.0', CFBundleSupportedPlatforms=['MacOSX'])
        signature = copy.deepcopy(self.signature)
        signature['com.apple.application-identifier'] = signature.pop('application-identifier')
        signature['com.apple.developer.aps-environment'] = signature.pop('aps-environment')
        signature.pop('get-task-allow', None)
        for key in ('app-sandbox', 'files.user-selected.read-write', 'network.client', 'network.server'):
            signature['com.apple.security.' + key] = True
        profile = copy.deepcopy(self.profile)
        profile['Entitlements'] = copy.deepcopy(signature)
        profile['Platform'] = ['OSX']
        return info, signature, profile

    def test_native_mac_store_profile_without_ios_only_keys(self):
        info, signature, profile = self.mac_checks()
        checks = verifier.metadata_checks(info, signature, profile, True, self.now, platform='macOS')
        self.assertTrue(all(checks.values()))
        self.assertNotIn('remoteNotificationBackground', checks)

    def test_mac_development_debug_and_unsandboxed_builds_are_rejected(self):
        for mutation in ('devices', 'debug', 'sandbox', 'catalyst', 'pcc'):
            info, signature, profile = self.mac_checks()
            if mutation == 'devices': profile['ProvisionedDevices'] = ['test-only-id']
            if mutation == 'debug': signature['com.apple.security.get-task-allow'] = True
            if mutation == 'sandbox': signature['com.apple.security.app-sandbox'] = False
            if mutation == 'catalyst': info['CFBundleSupportedPlatforms'] = ['iPhoneOS']
            if mutation == 'pcc': profile['Entitlements'].pop('com.apple.developer.private-cloud-compute')
            self.assertFalse(all(verifier.metadata_checks(info, signature, profile, True, self.now, platform='macOS').values()), mutation)

if __name__=='__main__': unittest.main()
