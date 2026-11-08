#!/usr/bin/env python3
"""Verify exported IPA locally; never uploads or prints provisioning contents."""
import datetime,hashlib,json,pathlib,plistlib,subprocess,tempfile,zipfile,sys,re
root=pathlib.Path(__file__).resolve().parents[1]
ipas=list((root/'build/ios/ipa').glob('*.ipa'))
if len(ipas)!=1:sys.exit('Expected exactly one exported IPA')
ipa=ipas[0]
with tempfile.TemporaryDirectory(prefix='smr-ipa-verify-') as temp:
    folder=pathlib.Path(temp)
    with zipfile.ZipFile(ipa) as z:z.extractall(folder)
    apps=list((folder/'Payload').glob('*.app'));assert len(apps)==1
    app=apps[0];info=plistlib.loads((app/'Info.plist').read_bytes())
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True,capture_output=True)
    profile=plistlib.loads(subprocess.run(['security','cms','-D','-i',str(app/'embedded.mobileprovision')],check=True,capture_output=True).stdout)
    entitlements=profile['Entitlements'];team=entitlements.get('com.apple.developer.team-identifier')
    assert info['CFBundleIdentifier']=='com.neotheone.sheetmusicrookie'
    assert info['CFBundleDisplayName']=='Sheet Music Rookie'
    version=re.search(r'^version:\s*([^\s]+)',(root/'pubspec.yaml').read_text(),re.M).group(1)
    name,build=version.split('+')
    assert info['CFBundleShortVersionString']==name
    assert info['CFBundleVersion']==build
    assert not entitlements.get('get-task-allow',False),'Development debugger entitlement present'
    assert not profile.get('ProvisionedDevices'),'Ad-hoc/development device list present'
    assert not profile.get('ProvisionsAllDevices',False),'Enterprise profile present'
    assert team=='C2M32YF6V7','Signing team changed'
    expiry=profile['ExpirationDate'];assert expiry>datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    result={'ipa':str(ipa.relative_to(root)),'sha256':hashlib.sha256(ipa.read_bytes()).hexdigest(),'bytes':ipa.stat().st_size,'signature_verification':'PASS','bundle_id':info['CFBundleIdentifier'],'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'team_preserved':True,'app_store_distribution_profile':True,'debugger_entitlement':False,'profile_expiration_utc':expiry.isoformat()+'Z','privacy_manifest_present':(app/'PrivacyInfo.xcprivacy').exists(),'sdk':info.get('DTSDKName')}
    assert result['privacy_manifest_present']
(root/'release/reports/ios-package-verification.json').write_text(json.dumps(result,indent=2)+'\n')
print('IPA signature, App Store distribution profile, identifiers, privacy resource and expiration checks passed')
