#!/usr/bin/env python3
"""Local-only native screenshot bridge, used by capture_store_screenshots.sh."""
import argparse, http.server, json, pathlib, subprocess, tempfile, shutil
p=argparse.ArgumentParser();p.add_argument('--device',required=True);p.add_argument('--group',required=True);p.add_argument('--port',type=int,default=8765);a=p.parse_args()
config=json.loads(pathlib.Path('scripts/store_targets.json').read_text())
out=pathlib.Path('store_assets/raw')/a.group;out.mkdir(parents=True,exist_ok=True)
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        name=self.path.removeprefix('/')
        if name=='health':
            self.send_response(200);self.end_headers();self.wfile.write(json.dumps({'group':a.group,'device':a.device}).encode());return
        if name not in config['screens']:
            self.send_error(404);return
        try:
            dest=out/(name+'.png')
            if a.group.startswith('iphone') or a.group=='ipad':
                with tempfile.TemporaryDirectory(prefix='smr-capture-') as temp:
                    native=pathlib.Path(temp)/'screen.png'
                    subprocess.run(['xcrun','simctl','io',a.device,'screenshot',str(native)],check=True)
                    shutil.copyfile(native,dest)
            else:
                import os
                adb=str(pathlib.Path(os.environ.get('ANDROID_HOME',str(pathlib.Path.home()/'Library/Android/sdk')))/'platform-tools/adb')
                with dest.open('wb') as f:subprocess.run([adb,'-s',a.device,'exec-out','screencap','-p'],stdout=f,check=True)
            self.send_response(200);self.end_headers();self.wfile.write(b'captured')
        except Exception as e:self.send_error(500,str(e))
http.server.HTTPServer(('127.0.0.1',a.port),Handler).serve_forever()
