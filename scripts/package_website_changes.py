#!/usr/bin/env python3
import argparse,difflib,hashlib,json,pathlib,shutil
p=argparse.ArgumentParser();p.add_argument('--source',type=pathlib.Path,default=pathlib.Path('../frtrev.github.io'));a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];stage=root/'release/website/frtrev.github.io';changes=root/'release/website/changes';changes.mkdir(parents=True,exist_ok=True)
manifest=[];patch=[]
for new in sorted(stage.rglob('*')):
    if not new.is_file():continue
    rel=new.relative_to(stage);old=a.source/rel
    data=new.read_bytes();before=old.read_bytes() if old.exists() else None
    if data==before:continue
    target=changes/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(new,target)
    manifest.append({'path':str(rel),'before_sha256':hashlib.sha256(before).hexdigest() if before is not None else None,'after_sha256':hashlib.sha256(data).hexdigest()})
    if new.suffix in ['.html','.css','.xml','.md']:
        patch+=list(difflib.unified_diff((before or b'').decode().splitlines(True),data.decode().splitlines(True),fromfile='a/'+str(rel) if before is not None else '/dev/null',tofile='b/'+str(rel)))
(root/'release/website/manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(root/'release/website/website.patch').write_text(''.join(patch))
print(f'{len(manifest)} additive/updated website files packaged')
