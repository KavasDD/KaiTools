"""Exercise the real chat process and local model protocol; no CAD or user key."""
import base64
import json
import os
import queue
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
EXE = ROOT / 'test-output/command-integration.exe'
mode = ''
seen = []


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        prompt = json.loads(body['messages'][1]['content'])
        assert self.headers['Authorization'] == 'Bearer dummy-loop-key'
        seen.append(prompt)
        result = dict(request_id=prompt['request_id'], message='下一步', action='place_text', text='检查电源')
        if mode == 'done' and prompt['tool_results']:
            assert prompt['tool_results'][0]['call']['text'] == '检查电源'
            result.update(action='reply', message='要求已按实际结果完成。')
        payload = json.dumps({'choices': [{'finish_reason': 'stop', 'message': {'content': json.dumps(result)}}]}).encode()
        self.send_response(200)
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def encoded(value):
    return base64.b64encode(value.encode('utf-8')).decode('ascii')


server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    for mode in ['done', 'native_error', 'context_error', 'partial_error', 'scope_changed', 'limit']:
        seen.clear()
        with tempfile.TemporaryDirectory(prefix='xiaokai-loop-') as temp:
            folder = Path(temp)
            config, connection, log = [folder / name for name in ['config.json', 'connection.json', 'chat.txt']]
            config.write_text(json.dumps(dict(Endpoint=f'http://127.0.0.1:{server.server_port}/v1', Model='fixture', Secret='dummy-loop-key')), 'utf-8')
            subprocess.run([str(EXE), '--roundtrip', str(config), str(connection), str(folder/'saved')], check=True, timeout=10)
            env = dict(os.environ, XIAOKAI_AI_TEST_CONNECTION=str(connection), XIAOKAI_COMMAND_TEST_QUESTION='请把要求做完', XIAOKAI_COMMAND_TEST_LOG=str(log))
            proc = subprocess.Popen([str(EXE), '--chat', 'orcad'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, encoding='utf-8', env=env)
            output = queue.Queue()
            def read_lines():
                for line in proc.stdout:
                    output.put(line.rstrip('\n'))
                output.put(None)
            reader = threading.Thread(target=read_lines, daemon=True)
            reader.start()
            calls = contexts = 0
            try:
                while True:
                    line = output.get(timeout=15)
                    if line is None:
                        break
                    fields = line.split('\t')
                    kind, request = fields[:2]
                    if kind == 'CONTEXT':
                        contexts += 1
                        if mode == 'context_error':
                            reply = 'ERROR\t' + request + '\t' + encoded('未执行：当前工程无法读取。')
                        else:
                            context = dict(platform='orcad', scope='B' if mode == 'scope_changed' and calls else 'A', parts=[], wires=[], default_spacing_mil=400, revision=calls)
                            reply = 'CTX\t' + request + '\t' + encoded(json.dumps(context))
                    elif kind == 'ACTION':
                        calls += 1
                        # An old step result must not be accepted by the next step.
                        proc.stdin.write('RESULT\t' + '0'*32 + '\t' + encoded('过期结果，不应出现在对话中') + '\n')
                        failed = mode == 'native_error' or mode == 'partial_error' and calls == 2
                        reply = ('ERROR' if failed else 'RESULT') + '\t' + request + '\t' + encoded('未执行：模拟原生写入失败。' if failed else f'已放置第{calls}个 Text。')
                    elif kind == 'CANCEL':
                        continue
                    else:
                        raise AssertionError(line)
                    proc.stdin.write(reply + '\n')
                    proc.stdin.flush()
                assert proc.wait(timeout=10) == 0
            finally:
                if proc.poll() is None:
                    proc.kill()
                proc.wait(timeout=10)
                proc.stdin.close()
                proc.stdout.close()
            transcript = log.read_text('utf-8')
            assert 'dummy-loop-key' not in transcript and '过期结果' not in transcript
            if mode == 'done':
                assert calls == 1 and len(seen) == 2 and contexts == 2
            elif mode == 'native_error':
                assert calls == 1 and len(seen) == 1 and contexts == 1 and '模拟原生写入失败' in transcript
            elif mode == 'context_error':
                assert calls == 0 and len(seen) == 0 and contexts == 1 and '工程无法读取' in transcript
            elif mode == 'partial_error':
                assert calls == 2 and len(seen) == 2 and contexts == 2
                assert '已放置第1个' in transcript and '模拟原生写入失败' in transcript
            elif mode == 'scope_changed':
                assert calls == 1 and len(seen) == 1 and contexts == 2 and '页面已切换' in transcript
            else:
                assert calls == 8 and len(seen) == 9 and contexts == 9 and '已执行8步' in transcript, (calls, len(seen), contexts, transcript[-800:])
            print('PASS:', mode, '- actual UI/model/pipe loop, fresh context and bounded native calls')
finally:
    server.shutdown()
