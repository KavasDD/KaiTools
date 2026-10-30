"""Local mock only: never loads or writes the user's provider settings."""
import base64
import json
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CS = Path('C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe')
TEST_EXE = ROOT / 'test-output' / 'ai-bridge-tests.exe'
PDF_DLLS = sorted((ROOT / 'vendor' / 'pdf-runtime').glob('*.dll'))
subprocess.run([str(CS), '/nologo', '/target:exe', '/define:AI_TEST', '/codepage:65001',
                '/r:System.dll', '/r:System.Core.dll', '/r:System.Drawing.dll',
                '/r:System.Windows.Forms.dll', '/r:System.Security.dll', '/r:System.Web.Extensions.dll',
                *('/r:' + str(p) for p in PDF_DLLS),
                *('/resource:' + str(p) + ',pdf.' + p.name for p in PDF_DLLS),
                '/out:' + str(TEST_EXE), str(ROOT / 'AiBridge.cs'), str(ROOT / 'Datasheets.cs'), str(ROOT / 'PanelJobs.cs'), str(ROOT / 'AiDiagnostics.cs'), str(ROOT / 'CommandAssistant.cs')], check=True)
subprocess.run([str(TEST_EXE), '--prompt-selftest'], check=True, timeout=10)

mode = 'valid'
seen = []
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self):
        data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        seen.append((self.path, self.headers.get('Authorization'), data))
        request = json.loads(data['messages'][1]['content'])
        if mode == 'slow': time.sleep(3)
        if mode == 'http_error':
            self.send_response(401); self.end_headers()
            self.wfile.write(b'secret-dummy-key echoed in upstream error'); return
        if mode.startswith('http_') and mode[5:].isdigit():
            status = int(mode[5:])
            body = json.dumps({'error': {'code': 'service_fixture', 'message': 'secret-dummy-key Bearer another-private-token limit reached'}}).encode()
            self.send_response(status); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body); return
        if mode == 'html_response':
            self.send_response(200); self.end_headers(); self.wfile.write(b'<html>proxy login</html>'); return
        if mode == 'html_content_type':
            self.send_response(200); self.send_header('Content-Type','text/html'); self.end_headers(); self.wfile.write(b'proxy login'); return
        if mode == 'unexpected_stream':
            self.send_response(200); self.send_header('Content-Type','text/event-stream'); self.end_headers(); self.wfile.write(b'data: {"choices": []}\n\n'); return
        if mode == 'redirect':
            self.send_response(302); self.send_header('Location', '/steal'); self.end_headers(); return
        answer = {'request_id': request['request_id'], 'findings': [
            {'id': f['id'], 'verdict': 'uncertain', 'evidence_ids': [f['id'] + '.DRC'],
             'reason': '缺少设计意图，不能仅凭未连接判断错误。', 'next_step': '核对 NC 标记及器件手册。', 'suggested_text': '检查此引脚是否有意悬空'}
            for f in request['findings']]}
        if mode == 'invented_id': answer['findings'][0]['id'] = 'F999'
        if mode == 'invented_evidence': answer['findings'][0]['evidence_ids'] = ['datasheet:imaginary']
        if mode == 'wrong_batch': answer['request_id'] = 'old-design'
        if mode == 'missing': answer['findings'] = []
        if mode == 'duplicate': answer['findings'] *= 2
        if mode == 'overconfident': answer['findings'][0]['verdict'] = 'error'
        if mode == 'multiline': answer['findings'][0]['suggested_text'] = 'line1\nline2'
        content = 'not JSON' if mode == 'malformed' else json.dumps(answer, ensure_ascii=False)
        if mode == 'fenced': content = '```json\n' + content + '\n```'
        if mode == 'prose': content = '以下是连接核查结果：\n```json\n' + content + '\n```\n请结合设计意图核对。'
        if mode == 'encoded': content = json.dumps(content, ensure_ascii=False)
        if mode == 'bom': content = '\ufeff' + content
        if mode == 'braces':
            answer['findings'][0]['reason'] = '名称包含 {DATA} 和 "引脚"，仍缺设计意图。'
            content = json.dumps(answer, ensure_ascii=False)
        if mode == 'retry_once' and len(data['messages']) == 2: content = '{"findings": ]}'
        if mode == 'retry_wrong_evidence':
            if len(data['messages']) == 2: content = '{"findings": ]}'
            else:
                answer['findings'][0]['evidence_ids'] = ['invented.datasheet']
                content = json.dumps(answer)
        if mode == 'bad_syntax': content = '{"request_id": "' + request['request_id'] + '", "findings": ]}'
        if mode == 'two_objects': content = content + '\n' + content
        if mode == 'array': content = '[' + content + ']'
        if mode == 'unclosed': content = content[:-2]
        if mode == 'refusal_text': content = '无法直接打开 DSN 文件。 secret-dummy-key Bearer another-private-token https://service.example/key'
        response = {'choices': [{'finish_reason': 'length' if mode == 'truncated' else 'stop',
                                  'message': {'content': content}}]}
        if mode == 'missing_choices': response = {'data': []}
        body = json.dumps(response).encode()
        self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers()
        try: self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError): pass

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='xiaokai-ai-tests-') as temp:
        folder = Path(temp)
        context = json.loads((ROOT / 'test-output' / 'ai-payload.json').read_text('utf-8-sig'))
        source = folder / 'request.json'; source.write_text(json.dumps(context), encoding='utf-8')
        config = folder / 'config.json'; config.write_text(json.dumps({
            'Endpoint': f'http://127.0.0.1:{server.server_port}/v1', 'Model': 'fixture-model',
            'Secret': 'secret-dummy-key', 'JsonMode': True}), encoding='utf-8')
        output = folder / 'result.tsv'; cancel = folder / 'cancel'
        encrypted = folder / 'stored.json'
        subprocess.run([str(TEST_EXE), '--roundtrip', str(config), str(encrypted), str(output)], check=True)
        assert output.read_text() == 'PASS'
        assert 'secret-dummy-key' not in encrypted.read_text('utf-8')
        print('PASS: actual Windows DPAPI save/load; credential absent from stored JSON')
        for case in ['valid', 'fenced', 'prose', 'encoded', 'bom', 'braces', 'retry_once', 'retry_wrong_evidence',
                     'bad_syntax', 'two_objects', 'array', 'unclosed', 'refusal_text', 'overconfident', 'invented_id', 'invented_evidence', 'wrong_batch',
                     'missing', 'duplicate', 'malformed', 'truncated', 'multiline', 'http_error',
                     'http_401', 'http_403', 'http_404', 'http_429', 'http_503', 'html_response', 'html_content_type', 'unexpected_stream', 'missing_choices', 'redirect', 'slow']:
            mode = case
            before_case = len(seen)
            output.unlink(missing_ok=True); cancel.unlink(missing_ok=True)
            p = subprocess.Popen([str(TEST_EXE), '--fixture', str(source), str(output), str(cancel), str(config)])
            if case == 'slow': time.sleep(.5); cancel.write_text('cancel')
            p.wait(timeout=12)
            result = output.read_text('utf-8')
            assert 'secret-dummy-key' not in result
            if case in ('valid', 'fenced', 'prose', 'encoded', 'bom', 'braces', 'retry_once', 'overconfident'):
                assert result.startswith('OK\t'), (case, result)
                fields = result.splitlines()[1].split('\t'); assert fields[1] == 'uncertain'
                assert base64.b64decode(fields[3]).decode() == '资料不足，未获得可判错的新依据。'
                assert len(base64.b64decode(fields[4]).decode()) <= 40
            else:
                assert result.startswith('ERROR\t'), (case, result)
                message = base64.b64decode(result.split('\t')[1]).decode()
                assert 'secret-dummy-key' not in message
                assert 'another-private-token' not in message
                if case == 'slow': assert '取消' in message
                if case.startswith('http_') and case[5:].isdigit():
                    assert ('HTTP ' + case[5:]) in message and 'service_fixture' in message, message
                if case in ('html_response', 'html_content_type'): assert 'HTML' in message and '/v1' in message and '接口响应' in message
                if case == 'unexpected_stream': assert 'stream=false' in message
                if case == 'missing_choices': assert 'choices' in message
                if case == 'malformed': assert '模型结论' in message
                if case == 'truncated': assert '长度上限' in message
                if case in ('bad_syntax', 'two_objects', 'array', 'unclosed', 'refusal_text'):
                    assert '重试后仍失败' in message and '模型返回片段' in message
                    assert len(seen) - before_case == 2
                if case == 'refusal_text':
                    assert '无法直接打开 DSN' in message
                    assert 'https://service.example' not in message
                if case == 'retry_wrong_evidence': assert '未提供的证据' in message
            if case == 'retry_once':
                assert len(seen) - before_case == 2
                retry_messages = seen[-1][2]['messages']
                assert [m['role'] for m in retry_messages] == ['system', 'user', 'assistant', 'user']
                assert retry_messages[1]['content'] == seen[-2][2]['messages'][1]['content']
            if case in ('invented_id', 'invented_evidence', 'wrong_batch', 'missing', 'duplicate'):
                assert len(seen) - before_case == 1, 'No retry of invalid evidence or targets'
            print('PASS:', case)
        assert all(path == '/v1/chat/completions' and auth == 'Bearer secret-dummy-key' for path, auth, _ in seen)
        assert seen[0][2]['response_format'] == {'type': 'json_object'}
        assert seen[0][2]['model'] == 'fixture-model'
        assert all('flat_net' not in d['messages'][1]['content'] for _, _, d in seen)
        mode = 'valid'
        cancel.unlink(missing_ok=True)
        # Bare origins infer /v1; explicit prefixes and full paths stay intact.
        for suffix, expected in [('', '/v1/chat/completions'), ('/', '/v1/chat/completions'),
                                 ('/v1/', '/v1/chat/completions'), ('/proxy/api', '/proxy/api/chat/completions'),
                                 ('/v1/chat/completions', '/v1/chat/completions')]:
            settings = json.loads(config.read_text()); settings['Endpoint'] = f'http://127.0.0.1:{server.server_port}' + suffix
            config.write_text(json.dumps(settings), encoding='utf-8')
            subprocess.run([str(TEST_EXE), '--fixture', str(source), str(output), str(cancel), str(config)], check=True, timeout=12)
            assert output.read_text('utf-8').startswith('OK\t') and seen[-1][0] == expected, (suffix, output.read_text('utf-8'), seen[-1][0])
        settings['Endpoint'] = f'http://127.0.0.1:{server.server_port}/v1'
        config.write_text(json.dumps(settings), encoding='utf-8')
        print('PASS: bare-domain /v1 default, explicit proxy prefix and full completion URL')
        launch = folder / 'ui-integration.tcl'
        script = (ROOT / 'ai-ui-integration-tests.tcl').as_posix()
        launch.write_text('try {source -encoding utf-8 {' + script + '}} on error {msg opts} {puts stderr [dict get $opts -errorinfo]; exit 1}\n', encoding='ascii')
        subprocess.run(['C:/orcad/Cadence/SPB_17.4/tcltk/bin/tclsh.exe', str(launch), str(TEST_EXE), str(config)], check=True, timeout=15)
        mode = 'refusal_text'
        subprocess.run(['C:/orcad/Cadence/SPB_17.4/tcltk/bin/tclsh.exe', str(launch), str(TEST_EXE), str(config), 'expect-failure'], check=True, timeout=15)
        # Insecure remote endpoints must be rejected before any network call.
        before = len(seen)
        for address in ['http://192.0.2.1/v1', 'https://example.com/v1?api_key=dummy', 'https://user:pass@example.com/v1']:
            settings = json.loads(config.read_text()); settings['Endpoint'] = address
            config.write_text(json.dumps(settings), encoding='utf-8')
            subprocess.run([str(TEST_EXE), '--fixture', str(source), str(output), str(cancel), str(config)], check=True)
            assert output.read_text().startswith('ERROR\t')
        assert len(seen) == before
        print('PASS: insecure endpoints, credential-bearing URLs and query strings rejected before network access')
        print('PASS: actual HTTP payload, compatible endpoint, auth, JSON option, cancellation, redacted errors and response validation')
finally:
    server.shutdown()
