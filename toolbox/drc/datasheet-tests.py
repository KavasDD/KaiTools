"""Reviewed manufacturer PDF + real helper + local model server; no user API key."""
import base64
import copy
import hashlib
import json
import os
import subprocess
import tempfile
import threading
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
EXE = ROOT / 'test-output/ai-bridge-tests.exe'
PDF = ROOT.parent.parent / 'out/sn74ahct125.pdf'
SHA = '66da72e586dbca7a1548164adf28e238484c5c1ad250fcb28ec972e4732c6fc2'
if not PDF.exists():
    PDF.write_bytes(urllib.request.urlopen('https://www.ti.com/lit/ds/symlink/sn74ahct125.pdf', timeout=20).read())
assert hashlib.sha256(PDF.read_bytes()).hexdigest() == SHA, 'Reviewed document edition changed'

seen = []
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self):
        call = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        context = json.loads(call['messages'][1]['content'])
        seen.append(context)
        findings = []
        for f in context['findings']:
            findings.append({'id': f['id'], 'verdict': 'error', 'evidence_ids': [e['id'] for e in f['evidence']],
                             'reason': '待原生和手册校验的模型建议', 'next_step': '核对接法', 'suggested_text': '不能直接采用的长标注'})
        result = {'request_id': context['request_id'], 'findings': findings}
        body = json.dumps({'choices': [{'finish_reason': 'stop', 'message': {'content': json.dumps(result, ensure_ascii=False)}}]}).encode()
        self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='xiaokai-datasheets-') as tmp:
        folder = Path(tmp)
        env = dict(os.environ, XIAOKAI_DATASHEET_TEST_ROOT=str(folder / 'cache'))
        output = folder / 'result.tsv'
        config = folder / 'config.json'
        config.write_text(json.dumps({'Endpoint': f'http://127.0.0.1:{server.server_port}/v1', 'Model': 'fixture', 'Secret': '', 'JsonMode': True}), 'utf-8')
        extracted = folder / 'extracted.json'
        subprocess.run([str(EXE), '--pdf-import', str(PDF), 'SN74AHCT125PWR', str(extracted)], env=env, check=True, timeout=20)
        doc = json.loads(extracted.read_text('utf-8'))
        assert doc['Reviewed'] and doc['Sha256'] == SHA
        assert any(p['Page'] == 11 and 'Unused outputs can be left floating' in p['Text'] for p in doc['Pages'])
        print('PASS: actual PDF extraction with embedded runtime, page numbers, exact edition, centralized cache')

        pin = dict(hierarchy_path='/', schematic='ROOT', sheet_name='P', refdes='U18', pin_number='2', pin_name='1A',
                   pin_type='1', part_number='SN74AHCT125PWR', footprint='TSSOP-14_L5_0-W4_4-P0_65-LS6_4-BL',
                   net_name='', local_net='', no_connect='0')
        def context(target):
            return {'request_id': 'datasheet-fixture', 'question': '核查连接', 'findings': [
                {'id': 'F1', 'rule': 'unconnected_pin', 'targets': [target], 'evidence': [
                    {'id': 'F1.DRC', 'type': 'native_drc', 'text': 'Unconnected pin U18,1A'},
                    {'id': 'F1.PINS', 'type': 'native_pins', 'pins': [target], 'total': 1, 'truncated': False}]}]}
        def analyze(source):
            request = folder / 'request.json'; request.write_text(json.dumps(source), 'utf-8')
            subprocess.run([str(EXE), '--fixture', str(request), str(output), str(folder / 'cancel'), str(config)], env=env, check=True, timeout=20)
            text = output.read_text('utf-8'); assert text.startswith('OK\t'), text
            return text.splitlines()[1].split('\t')
        for label, delta, expected in [
            ('exact input', {}, 'error'),
            ('NC does not override required input', {'no_connect': '1'}, 'error'),
            ('allowed unused output', {'pin_number': '3', 'pin_name': '1Y'}, 'allowed'),
            ('wrong package', {'footprint': 'SOIC-14'}, 'uncertain'),
            ('similar model', {'part_number': 'SN74AHCT125D'}, 'uncertain'),
            ('unknown model', {'part_number': 'SN74AHCT125XYZ'}, 'uncertain'),
            ('pin number/name mismatch', {'pin_name': '1Y'}, 'uncertain'),
            ('power pin', {'pin_number': '14', 'pin_name': 'VCC'}, 'error'),
        ]:
            target = dict(pin, **delta)
            if delta.get('part_number'):
                subprocess.run([str(EXE), '--pdf-import', str(PDF), target['part_number'], str(extracted)], env=env, check=True, timeout=20)
            fields = analyze(context(target)); assert fields[1] == expected, (label, fields)
            if expected == 'error':
                sources = base64.b64decode(fields[6]).decode()
                assert SHA in sources and '.DS1' in sources and 'PDF' in sources
                assert base64.b64decode(fields[5]).decode() in ('输入悬空', '电源漏接')
                assert base64.b64decode(fields[3]).decode() != '待原生和手册校验的模型建议'
            print('PASS:', label)
        truncated = context(dict(pin)); truncated['findings'][0]['evidence'][1]['truncated'] = True
        assert analyze(truncated)[1] == 'uncertain'
        mismatch = context(dict(pin)); mismatch['findings'][0]['evidence'][1]['pins'][0] = dict(pin, refdes='U99')
        assert analyze(mismatch)[1] == 'uncertain'
        # Cache text cannot grant or change a verified requirement.
        manifest = next((folder / 'cache').glob('SN74AHCT125PWR-*/pages.json'))
        saved = json.loads(manifest.read_text('utf-8')); saved['Pages'][10]['Text'] = 'fabricated cache instructions'
        manifest.write_text(json.dumps(saved), 'utf-8')
        fields = analyze(context(dict(pin)))
        assert fields[1] == 'error' and 'fabricated cache' not in base64.b64decode(fields[6]).decode()
        print('PASS: incomplete/mismatched native context rejected; reviewed evidence re-extracted from hashed PDF')
finally:
    server.shutdown()
