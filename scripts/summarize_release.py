#!/usr/bin/env python3
import csv,datetime,json,pathlib,re
from zoneinfo import ZoneInfo
root=pathlib.Path(__file__).resolve().parents[1];reports=root/'release/reports'
status=reports/'run-status.tsv'
steps=list(csv.DictReader(status.open(),delimiter='\t')) if status.exists() else []
def read_json(path):
    file=root/path
    return json.loads(file.read_text()) if file.exists() else None
images=read_json('store_assets/validation/images.json')
website=read_json('release/reports/website-links.json')
ipa=read_json('release/reports/ios-package-verification.json')
lines=['# Automated release preparation report','', 'Generated '+datetime.datetime.now(ZoneInfo('America/Chicago')).isoformat(timespec='seconds')+'.','', '| Step | Status | Exit |','|---|---|---|']
for s in steps:lines.append(f'| {s["step"]} | {s["status"]} | {s["exit_code"]} |')
lines+=['','## Asset and package checks','']
if images:lines.append(f'- Image validation: {"PASS" if images["passed"] else "FAIL"}; {sum(r["status"]=="PASS" for r in images["files"])}/{len(images["files"])} checks passed.')
if website:lines.append(f'- Website links: {website["status"]}; {website["links_checked"]} links across {website["html_files"]} HTML files.')
if ipa:lines.append(f'- IPA local signature/profile verification: {ipa["signature_verification"]}; SHA-256 `{ipa["sha256"]}`. Confirm this hash matches the exported binary from the current successful build.')
lines+=['','Technical image validation must be combined with successful native capture and visual review. Missing or failed build steps are not satisfied by an artifact from a previous run. Read release/README.md and the owner submission checklist before uploading. No publishing is performed.','']
(reports/'automated-run.md').write_text('\n'.join(lines))
print(reports/'automated-run.md')
