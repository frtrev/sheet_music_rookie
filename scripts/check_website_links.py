#!/usr/bin/env python3
import argparse,html.parser,json,pathlib,urllib.parse,sys
p=argparse.ArgumentParser();p.add_argument('root',type=pathlib.Path);a=p.parse_args();root=a.root.resolve();errors=[];checked=0
class Parser(html.parser.HTMLParser):
    def __init__(self):super().__init__();self.links=[];self.ids=set()
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if 'id' in attrs:self.ids.add(attrs['id'])
        for k in ['href','src']:
            if k in attrs:self.links.append(attrs[k])
parsed={}
for file in root.rglob('*.html'):
    obj=Parser();obj.feed(file.read_text());parsed[file]=obj
for file,obj in parsed.items():
    for link in obj.links:
        u=urllib.parse.urlsplit(link)
        if u.scheme or u.netloc:continue
        target=(root/u.path.lstrip('/') if u.path.startswith('/') else file.parent/u.path) if u.path else file
        target=target.resolve()
        if target.is_dir():target=target/'index.html'
        checked+=1
        if not target.exists():errors.append({'source':str(file.relative_to(root)),'link':link,'reason':'missing target'})
        elif u.fragment and target in parsed and urllib.parse.unquote(u.fragment) not in parsed[target].ids:errors.append({'source':str(file.relative_to(root)),'link':link,'reason':'missing fragment'})
report={'root':str(root),'html_files':len(parsed),'links_checked':checked,'errors':errors,'status':'PASS' if not errors else 'FAIL'}
out=pathlib.Path('release/reports/website-links.json');out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));sys.exit(bool(errors))
