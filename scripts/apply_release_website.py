#!/usr/bin/env python3
"""Apply the reviewed local website package; never commits/pushes/deploys."""
import argparse,hashlib,json,pathlib,shutil,sys
p=argparse.ArgumentParser();p.add_argument('--target',type=pathlib.Path,required=True);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];bundle=root/'release/website';manifest=json.loads((bundle/'manifest.json').read_text())
for entry in manifest:
    rel=pathlib.Path(entry['path']);assert not rel.is_absolute() and '..' not in rel.parts
    source=bundle/'changes'/rel;assert hashlib.sha256(source.read_bytes()).hexdigest()==entry['after_sha256']
    target=a.target/rel;actual=hashlib.sha256(target.read_bytes()).hexdigest() if target.exists() else None
    if actual not in [entry['before_sha256'],entry['after_sha256']]:sys.exit(f'Refusing to overwrite changed website file: {rel}')
for entry in manifest:
    rel=pathlib.Path(entry['path']);target=a.target/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(bundle/'changes'/rel,target)
print(f'Applied {len(manifest)} local website changes; no commit/push/deployment')
