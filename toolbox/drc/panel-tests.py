"""Real winexe helper and Tk panels, isolated settings/cache and local HTTP only."""
import json
import os
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DLLS = sorted((ROOT / 'vendor/pdf-runtime').glob('*.dll'))
EXE = ROOT / 'test-output/panel-tests.exe'
subprocess.run(['C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe', '/nologo',
                '/target:winexe', '/define:AI_TEST', '/codepage:65001',
                *('/r:' + p for p in ['System.dll', 'System.Core.dll', 'System.Drawing.dll',
                                     'System.Windows.Forms.dll', 'System.Security.dll', 'System.Web.Extensions.dll']),
                *('/r:' + str(p) for p in DLLS),
                *('/resource:' + str(p) + ',pdf.' + p.name for p in DLLS), '/out:' + str(EXE),
                *(str(ROOT / p) for p in ['AiBridge.cs', 'Datasheets.cs', 'PanelJobs.cs', 'AiDiagnostics.cs', 'CommandAssistant.cs'])], check=True)

seen = []
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        assert self.path == '/v1/models'
        assert self.headers.get('Authorization') == 'Bearer dummy-panel-key'
        body = json.dumps({'data': [{'id': 'second-model'}, {'id': 'fixture-model'}, {'id': 'second-model'}]}).encode()
        self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        assert self.path == '/v1/chat/completions'
        seen.append(self.headers.get('Authorization'))
        self.rfile.read(int(self.headers['Content-Length']))
        failed = self.headers.get('Authorization') == 'Bearer wrong-draft-key'
        body = json.dumps({'error': {'code': 'invalid_api_key', 'message': 'Invalid key: wrong-draft-key'}} if failed else
                          {'choices': [{'finish_reason': 'stop', 'message': {'content': 'OK'}}]}).encode()
        self.send_response(401 if failed else 200); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='xiaokai-panel-') as tmp:
        folder = Path(tmp)
        config = folder / 'connection.json'
        env = dict(os.environ, XIAOKAI_AI_TEST_CONNECTION=str(config),
                   XIAOKAI_DATASHEET_TEST_ROOT=str(folder / 'cache'))
        script = folder / 'test.tcl'
        script.write_text('source -encoding utf-8 {' + str(ROOT / 'single-window-tests.tcl').replace('\\', '/') + '}')
        subprocess.run(['C:/orcad/Cadence/SPB_17.4/tcltk/bin/tclsh.exe', str(script), str(EXE),
                        str(ROOT.parent.parent / 'out/sn74ahct125.pdf'), f'http://127.0.0.1:{server.server_port}'],
                       env=env, check=True, timeout=120)
        assert seen == ['Bearer dummy-panel-key', 'Bearer wrong-draft-key']
        assert 'dummy-panel-key' not in config.read_text('utf-8')
        assert not list(folder.rglob('*.tmp'))
        print('PASS: winexe stdin transport, existing Key retained on test, encrypted config, no user settings or engineering changes')
finally:
    server.shutdown()
