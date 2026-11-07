#!/usr/bin/env python3
import argparse,json,pathlib,plistlib,xml.etree.ElementTree as ET
root=pathlib.Path(__file__).resolve().parents[1];report={}
# Inspect release merged manifests if generated, never substitute debug manifests.
files=list((root/'build/app/intermediates').glob('merged_manifests/release/**/AndroidManifest.xml'))+list((root/'build/app/intermediates').glob('merged_manifest/release/**/AndroidManifest.xml'))
report['android']={'release_manifests':[]}
ns='{http://schemas.android.com/apk/res/android}'
for file in files:
    tree=ET.parse(file);r=tree.getroot();sdk=r.find('uses-sdk');app=r.find('application')
    permissions=[e.get(ns+'name') for e in r.findall('uses-permission')]
    result={'file':str(file.relative_to(root)), 'package':r.get('package'), 'permissions':permissions,'min_sdk':sdk.get(ns+'minSdkVersion') if sdk is not None else None,'target_sdk':sdk.get(ns+'targetSdkVersion') if sdk is not None else None,'debuggable':app.get(ns+'debuggable','false') if app is not None else None}
    result['unexpected_permissions']=[p for p in permissions if p not in ['android.permission.RECORD_AUDIO','android.permission.WAKE_LOCK','android.permission.MODIFY_AUDIO_SETTINGS','com.sheetmusicrookie.sheet_music_rookie.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION']]
    report['android']['release_manifests'].append(result)
report['ios']={'archives':[]}
for archive in [root/'build/ios/archive/Runner.xcarchive',root/'release/ios/unsigned-verification.xcarchive']:
    if not archive.exists():continue
    apps=list((archive/'Products/Applications').glob('*.app'))
    for app in apps:
        info=plistlib.loads((app/'Info.plist').read_bytes())
        manifests=[]
        for file in app.rglob('*.xcprivacy'):
            manifests.append({'path':str(file.relative_to(app)), 'declarations':plistlib.loads(file.read_bytes())})
        report['ios']['archives'].append({'archive':str(archive.relative_to(root)), 'bundle_id':info.get('CFBundleIdentifier'),'version':info.get('CFBundleShortVersionString'),'build':info.get('CFBundleVersion'),'minimum_os':info.get('MinimumOSVersion'),'device_families':info.get('UIDeviceFamily'),'sdk':info.get('DTSDKName'),'microphone_message':info.get('NSMicrophoneUsageDescription'),'privacy_manifests':manifests})
out=root/'release/reports/native-artifact-audit.json';out.write_text(json.dumps(report,indent=2)+'\n');print(out)
