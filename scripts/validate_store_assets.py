#!/usr/bin/env python3
"""Strict upload image validation using Python's standard library only."""
import argparse, csv, hashlib, json, pathlib, struct, sys, zlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--group');a=p.parse_args()
config=json.loads((ROOT/'scripts/store_targets.json').read_text());rows=[]
def inspect(path, size, category, max_bytes=8*1024*1024, alpha=False):
    row={'filename':str(path.relative_to(ROOT)), 'actual_dimensions':'missing','target_dimensions':f'{size[0]}x{size[1]}','device_class':category,'format':'unknown','bytes':0,'status':'FAIL','reason':''}
    try:
        data=path.read_bytes();row['bytes']=len(data)
        assert data[:8]==b'\x89PNG\r\n\x1a\n','not PNG'
        w,h,depth,color=struct.unpack('>IIBB',data[16:26]);row.update(actual_dimensions=f'{w}x{h}',format=f'PNG/{depth}-bit/color-type-{color}',sha256=hashlib.sha256(data).hexdigest())
        assert [w,h]==size,'wrong exact dimensions'
        assert depth==8,'must be 8-bit per channel'
        assert color==(6 if alpha else 2),'must be RGBA' if alpha else 'must be opaque RGB'
        assert len(data)<=max_bytes,'file too large'
        # Decode IDAT and verify all chunks/CRCs; reject suspiciously blank captures.
        pos=8;compressed=b'';iend=False
        while pos<len(data):
            length=struct.unpack('>I',data[pos:pos+4])[0];kind=data[pos+4:pos+8];payload=data[pos+8:pos+8+length]
            crc=struct.unpack('>I',data[pos+8+length:pos+12+length])[0]
            assert zlib.crc32(kind+payload)&0xffffffff==crc,'PNG CRC error'
            if kind==b'IDAT':compressed+=payload
            if kind==b'IEND':iend=True
            pos+=length+12
        raw=zlib.decompress(compressed);channels=4 if alpha else 3
        assert len(raw)==h*(1+w*channels),'unexpected PNG scanline length'
        assert iend,'missing IEND'
        assert len(set(raw))>16 and len(compressed)>20000,'blank or nearly empty image'
        if category.startswith('Google Play') and 'graphic' not in category and 'icon' not in category:
            assert 320<=min(w,h) and max(w,h)<=3840 and max(w,h)<=2*min(w,h),'Google dimension/aspect constraint'
        row['status']='PASS'
    except Exception as e:row['reason']=str(e)
    rows.append(row)
for key,g in config['groups'].items():
    if a.group and key!=a.group:continue
    folder=ROOT/'store_assets'/g['path'];files=list(folder.glob('*.png'))
    for name in config['screens']:inspect(folder/(name+'.png'),g['size'],g['category'])
    if not g['min']<=len(files)<=g['max']:
        rows.append({'filename':str(folder.relative_to(ROOT)), 'status':'FAIL','reason':f'count {len(files)} outside {g["min"]}..{g["max"]}'})
    hashes=[r.get('sha256') for r in rows if r.get('device_class')==g['category'] and r.get('sha256')]
    if len(hashes)!=len(set(hashes)):
        rows.append({'filename':str(folder.relative_to(ROOT)), 'status':'FAIL','reason':'duplicate screenshots; inspect foreground app/system dialogs'})
    extras={f.stem for f in files}-set(config['screens'])
    if extras:rows.append({'filename':str(folder),'status':'FAIL','reason':f'unconfigured screenshots: {sorted(extras)}'})
if not a.group:
    for name,g in config['graphics'].items():inspect(ROOT/'store_assets'/name,g['size'],'Google Play '+('icon' if g['alpha'] else 'feature graphic'),g['max_bytes'],g['alpha'])
report=ROOT/'store_assets/validation';report.mkdir(parents=True,exist_ok=True)
suffix='-'+a.group if a.group else ''
(report/f'images{suffix}.json').write_text(json.dumps({'verified_on':config['verified_on'],'passed':all(r['status']=='PASS' for r in rows),'files':rows},indent=2)+'\n')
with (report/f'images{suffix}.csv').open('w') as f:
    writer=csv.DictWriter(f,fieldnames=['filename','actual_dimensions','target_dimensions','device_class','format','bytes','status','reason','sha256']);writer.writeheader();writer.writerows(rows)
print(f'{sum(r["status"]=="PASS" for r in rows)}/{len(rows)} asset checks passed; report: {report}/images{suffix}.json')
sys.exit(0 if all(r['status']=='PASS' for r in rows) else 1)
