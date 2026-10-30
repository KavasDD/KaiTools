"""Chat + mocked model + real native label edits on a copy of the style fixture."""
import json
import os
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
EXE = ROOT / 'test-output/command-labels-integration.exe'
pdf_dlls = sorted((ROOT / 'vendor/pdf-runtime').glob('*.dll'))
subprocess.run([
    'C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe', '/nologo', '/target:winexe', '/define:AI_TEST', '/codepage:65001',
    *('/r:' + name for name in ['System.dll', 'System.Core.dll', 'System.Drawing.dll', 'System.Windows.Forms.dll', 'System.Security.dll', 'System.Web.Extensions.dll']),
    *('/r:' + str(p) for p in pdf_dlls), *('/resource:' + str(p) + ',pdf.' + p.name for p in pdf_dlls), '/out:' + str(EXE),
    *(str(ROOT / name) for name in ['AiBridge.cs', 'Datasheets.cs', 'PanelJobs.cs', 'AiDiagnostics.cs', 'CommandAssistant.cs'])
], check=True)
seen = []


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        payload = json.loads(request['messages'][1]['content'])
        seen.append(payload)
        assert self.headers['Authorization'] == 'Bearer dummy-label-key'
        assert 'rename_net_labels' in request['messages'][0]['content']
        current = json.loads(payload['current'])
        labels = current['labels']
        answer = {'request_id': payload['request_id'], 'message': '核对名称对象'}
        if payload['tool_results']:
            result = payload['tool_results'][-1]
            assert result['call']['action'] == 'rename_net_labels'
            assert '6 个同名标签（2 页）' in result['result']
            assert all(any(l['kind'] == 'alias' and l['name'] == f'MCU_DIO{i}' for l in labels) for i in range(3))
            assert all(any(l['kind'] == 'offpage' and l['name'] == f'MCU_M{i}' and l['recent'] for l in labels) for i in range(3))
            assert not any(l['name'].startswith('MCU_MDI') and l['name'][-1:] in '012' for l in labels)
            answer.update(action='reply', message='已核对：后面一组去掉 DI，前面一组保留。')
        else:
            targets = [l for l in labels if l['kind'] == 'offpage' and l['name'] in ['MCU_MDI0', 'MCU_MDI1', 'MCU_MDI2']]
            targets.sort(key=lambda l: l['name'])
            assert len(targets) == 3 and all(l['selected'] for l in targets)
            answer.update(action='rename_net_labels', label_indices=[l['index'] for l in targets], names=['MCU_M0', 'MCU_M1', 'MCU_M2'])
        body = json.dumps({'choices': [{'finish_reason': 'stop', 'message': {'content': json.dumps(answer)}}]}).encode()
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='xiaokai-label-chat-') as temp:
        folder = Path(temp)
        config = folder / 'config.json'
        connection = folder / 'connection.json'
        chatlog = folder / 'chat.txt'
        config.write_text(json.dumps({'Endpoint': f'http://127.0.0.1:{server.server_port}/v1', 'Model': 'fixture', 'Secret': 'dummy-label-key'}), 'utf-8')
        subprocess.run([str(EXE), '--roundtrip', str(config), str(connection), str(folder / 'roundtrip')], check=True, timeout=10)
        script = r'''
fconfigure stdout -encoding utf-8
try {
    load {C:/orcad/Cadence/SPB_17.4/tools/bin/orDb_Dll_Tcl64.dll} DboTclWriteBasic
    source {PLUGIN}
    file copy {D:/selfsoftware/out/style-reference.dsn} {FIXTURE}
    set state [DboState];set session [DboTclHelper_sCreateSession]
    set c [DboTclHelper_sMakeCString {FIXTURE}];set design [$session GetDesignAndSchematics $c $state];DboTclHelper_sDeleteCString $c
    set page [::xiaokai::drc::reviewPage $design MCU S03_PORT]
    proc GetActivePage {} {return $::page}
    proc ::xiaokai::drc::activeDesign {} {return $::design}
    set selected {}
    foreach row [::xiaokai::drc::commandWires $page] {
        if {[llength [lsearch -all -inline -regexp [dict get $row names] {^MCU_MDI[012]$}]]} {lappend selected [dict get $row object]}
    }
    proc GetSelectedObjects {} {return $::selected}
    rename ::xiaokai::drc::aiHelper ::xiaokai::drc::savedHelper
    proc ::xiaokai::drc::aiHelper {} {return {HELPER}}
    set before [::xiaokai::drc::commandPinPartition [::xiaokai::drc::snapshot $design]]
    ::xiaokai::drc::commandOpen
    set deadline [expr {[clock milliseconds]+20000}]
    while {$::xiaokai::drc::commandChannel ne ""} {
        update;after 20
        if {[clock milliseconds]>$deadline} {error "Label chat timeout"}
    }
    if {[::xiaokai::drc::commandPinPartition [::xiaokai::drc::snapshot $design]] ne $before} {error "Pin partition changed"}
    puts "PASS: selected connected wires with two name groups -> model label indices -> six native edits across two pages -> fresh context/result verification"
} on error {msg opts} {puts stderr [dict get $opts -errorinfo];exit 1}
exit 0
'''
        for key, value in {'PLUGIN': ROOT.parent.parent / 'autoload/drctoolMenu.tcl', 'FIXTURE': folder / 'test.dsn', 'HELPER': EXE}.items():
            script = script.replace(key, str(value).replace('\\', '/'))
        target = folder / 'integration.tcl'
        target.write_text(script, 'utf-8')
        env = dict(os.environ, XIAOKAI_AI_TEST_CONNECTION=str(connection), XIAOKAI_COMMAND_TEST_QUESTIONS='选中的三条线上各有两个名字，后面 MCU_MDI0、MCU_MDI1、MCU_MDI2 这组去掉 DI，前面的 MCU_DIO0 到 MCU_DIO2 不变', XIAOKAI_COMMAND_TEST_LOG=str(chatlog))
        subprocess.run(['C:/orcad/Cadence/SPB_17.4/tcltk/bin/tclsh.exe', str(target)], check=True, timeout=30, env=env)
        log = chatlog.read_text('utf-8')
        assert len(seen) == 2 and 'dummy-label-key' not in log
        assert '6 个同名标签（2 页）' in log and '后面一组去掉 DI' in log
finally:
    server.shutdown()
