import json
import os
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
root=Path(__file__).resolve().parent
driver=root/'test-output/command-ui-checks.exe'
subprocess.run(['C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe','/nologo','/target:exe','/r:System.Windows.Forms.dll','/r:System.Drawing.dll','/out:'+str(driver),str(root/'CommandUiChecks.cs')],check=True)
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_GET(self):
        assert self.path=='/v1/models' and self.headers['Authorization']=='Bearer dummy-ui-key'
        body=json.dumps({'data':[{'id':'second-model'},{'id':'fixture-model'}]}).encode()
        self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='xiaokai-command-ui-') as folder:
        config=Path(folder)/'connection.json'
        env=dict(os.environ,XIAOKAI_AI_TEST_CONNECTION=str(config))
        subprocess.run([str(driver),str(root/'test-output/command-integration.exe'),f'http://127.0.0.1:{server.server_port}',str(root/'test-output/command-settings.png')],env=env,check=True,timeout=30)
        assert 'dummy-ui-key' not in config.read_text('utf-8')
finally:server.shutdown()
