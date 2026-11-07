#!/usr/bin/env python3
"""Inventory actual locked native plugins, privacy manifests and Android permissions."""
import json,pathlib,plistlib,xml.etree.ElementTree as ET
root=pathlib.Path(__file__).resolve().parents[1];data=json.loads((root/'.flutter-plugins-dependencies').read_text());report={'plugins':{},'app_source_network_clients':[]}
for platform in ['ios','android']:
    report['plugins'][platform]=[]
    for p in data['plugins'][platform]:
        base=pathlib.Path(p['path']);entry={'name':p['name'],'version_source':base.name,'development_dependency':p.get('dev_dependency',False)}
        if platform=='ios':
            entry['privacy_manifests']=[]
            for f in base.rglob('*.xcprivacy'):
                entry['privacy_manifests'].append({'path':str(f.relative_to(base)), 'declarations':plistlib.loads(f.read_bytes())})
        else:
            entry['manifest_permissions']=[]
            for f in (base/'android/src/main').glob('AndroidManifest.xml'):
                tree=ET.parse(f)
                entry['manifest_permissions'] += [e.attrib.get('{http://schemas.android.com/apk/res/android}name') for e in tree.findall('uses-permission')]
        report['plugins'][platform].append(entry)
out=root/'release/reports/dependency-audit.json';out.write_text(json.dumps(report,indent=2)+'\n');print(out)
