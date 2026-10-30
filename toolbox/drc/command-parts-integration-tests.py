"""Real chat, local mocked API, native component tools on a disposable design."""
import json
import os
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
EXE = ROOT / 'test-output/command-parts-integration.exe'
dlls = sorted((ROOT / 'vendor/pdf-runtime').glob('*.dll'))
subprocess.run([
    'C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe', '/nologo', '/target:winexe', '/define:AI_TEST', '/codepage:65001',
    *('/r:' + name for name in ['System.dll', 'System.Core.dll', 'System.Drawing.dll', 'System.Windows.Forms.dll', 'System.Security.dll', 'System.Web.Extensions.dll']),
    *('/r:' + str(p) for p in dlls), *('/resource:' + str(p) + ',pdf.' + p.name for p in dlls), '/out:' + str(EXE),
    *(str(ROOT / name) for name in ['AiBridge.cs', 'Datasheets.cs', 'PanelJobs.cs', 'AiDiagnostics.cs', 'CommandAssistant.cs'])
], check=True)
seen = []
errors = []


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        try:
            request = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            payload = json.loads(request['messages'][1]['content'])
            seen.append(payload)
            assert self.headers['Authorization'] == 'Bearer dummy-parts-key'
            system = request['messages'][0]['content']
            assert 'copy_parts' in system and '复制个CN10出来应调用copy_parts' in system
            parts = json.loads(payload['current'])['parts']
            results = payload['tool_results']
            step = len(results)
            answer = {'request_id': payload['request_id'], 'message': '核对器件操作'}
            if step == 0:
                source = next(p for p in parts if p['ref'] == 'CN10')
                answer.update(action='copy_parts', target_indices=[source['index']])
            else:
                source = next(p for p in parts if p['ref'] == 'CN10')
                assert source['value'] == 'CON_DIP_V_25X2_0_254' and not source['recent']
                recent = [p for p in parts if p['recent']]
                assert len(recent) == 1 and recent[0]['ref'] != 'CN10'
                clone = recent[0]
                assert all('已' in r['result'] for r in results)
                assert all(isinstance(r['call']['parameters'], dict) and r['call']['parameters']['target_indices'] for r in results)
                if step == 1:
                    assert clone['ref'] == 'CN11' and clone['value'] == source['value']
                    assert clone['properties']['PCB Footprint'] == source['properties']['PCB Footprint']
                    answer.update(action='set_part_property', target_indices=[clone['index']], property='Value', values=['CHAT-CLONE'])
                elif step == 2:
                    assert clone['value'] == 'CHAT-CLONE'
                    answer.update(action='move_parts', target_indices=[clone['index']], placement='pick')
                elif step == 3:
                    answer.update(action='rotate_parts', target_indices=[clone['index']], angle_degrees=90)
                elif step == 4:
                    assert clone['rotation_degrees'] == 90
                    answer.update(action='mirror_parts', target_indices=[clone['index']], axis='vertical')
                elif step == 5:
                    answer.update(action='rename_parts', target_indices=[clone['index']], references=['CN99'])
                elif step == 6:
                    assert clone['ref'] == 'CN99' and clone['value'] == 'CHAT-CLONE'
                    assert [r['call']['action'] for r in results] == ['copy_parts', 'set_part_property', 'move_parts', 'rotate_parts', 'mirror_parts', 'rename_parts']
                    answer.update(action='reply', message='已复制 CN10，新器件 CN99 的参数、位置和方向均已核对。')
                else:
                    raise AssertionError('Repeated tools')
            body = json.dumps({'choices': [{'finish_reason': 'stop', 'message': {'content': json.dumps(answer)}}]}).encode()
            self.send_response(200)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except Exception as exc:
            errors.append(repr(exc))
            self.send_error(500)


server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='xiaokai-parts-chat-') as temp:
        folder = Path(temp)
        config = folder / 'config.json'
        connection = folder / 'connection.json'
        log = folder / 'chat.txt'
        config.write_text(json.dumps({'Endpoint': f'http://127.0.0.1:{server.server_port}/v1', 'Model': 'fixture', 'Secret': 'dummy-parts-key'}), 'utf-8')
        subprocess.run([str(EXE), '--roundtrip', str(config), str(connection), str(folder / 'roundtrip')], check=True, timeout=10)
        script = r'''
fconfigure stdout -encoding utf-8
try {
    set ::env(CDSROOT) {C:/orcad/Cadence/SPB_17.4};set ::env(PATH) "C:/orcad/Cadence/SPB_17.4/tools/bin;$::env(PATH)"
    load {C:/orcad/Cadence/SPB_17.4/tools/bin/orDb_Dll_Tcl64.dll} DboTclWriteBasic
    source {PLUGIN}
    file copy {D:/selfsoftware/out/style-reference.dsn} {FIXTURE}
    set state [DboState];set session [DboTclHelper_sCreateSession]
    set c [DboTclHelper_sMakeCString {FIXTURE}];set design [$session GetDesignAndSchematics $c $state];DboTclHelper_sDeleteCString $c
    set page [::xiaokai::drc::reviewPage $design MCU S03_PORT]
    proc GetActivePage {} {return $::page}
    proc ::xiaokai::drc::activeDesign {} {return $::design}
    rename ::xiaokai::drc::aiHelper ::xiaokai::drc::savedHelper
    proc ::xiaokai::drc::aiHelper {} {return {HELPER}}
    set before [::xiaokai::drc::snapshot $design]
    set oldIds [lsort -unique [lmap pin [dict get $before pins] {dict get $pin _part_id}]]
    ::xiaokai::drc::commandOpen
    proc GetLastMouseClickPointOnPage {} {return $::testClick}
    proc emulateClick {} {
        if {[llength $::xiaokai::drc::commandPick]} {
            set context [dict get $::xiaokai::drc::commandPick context]
            set ids [dict get $::xiaokai::drc::commandFocus ids]
            lassign [::xiaokai::drc::commandPartBlank $context {} 400 400 $ids {}] x y
            # Picker coordinates are top-left of the component's padded bounding box.
            set ::testClick [list [expr {($x+100)/double([$::page GetPhysicalGranularity])}] [expr {($y+100)/double([$::page GetPhysicalGranularity])}]]
            ::xiaokai::drc::commandPickApply
        }
        if {$::xiaokai::drc::commandChannel ne ""} {after 100 emulateClick}
    }
    after 100 emulateClick
    set deadline [expr {[clock milliseconds]+30000}]
    while {$::xiaokai::drc::commandChannel ne ""} {
        update;after 20
        if {[clock milliseconds]>$deadline} {error "Component chat timeout"}
    }
    set after [::xiaokai::drc::snapshot $design]
    if {[::xiaokai::drc::commandPartLogical $before $oldIds] ne [::xiaokai::drc::commandPartLogical $after $oldIds]} {error "Original circuit changed"}
    set context [::xiaokai::drc::commandContext]
    if {[llength [dict get $context parts]] != 38} {error "Unexpected component count"}
    ::xiaokai::drc::reviewCheckStatus [$session MarkAllLibForSave $design]
    ::xiaokai::drc::reviewCheckStatus [$session SaveDesign $design]
    puts "PASS: chat/model/native copy -> fresh recent target -> property -> picked move -> rotate -> mirror -> rename, original circuit verified"
} on error {msg opts} {puts stderr [dict get $opts -errorinfo];exit 1}
exit 0
'''
        for key, value in {'PLUGIN': ROOT.parent.parent / 'autoload/drctoolMenu.tcl', 'FIXTURE': folder / 'test.dsn', 'HELPER': EXE}.items():
            script = script.replace(key, str(value).replace('\\', '/'))
        target = folder / 'integration.tcl'
        target.write_text(script, 'utf-8')
        env = dict(os.environ, XIAOKAI_AI_TEST_CONNECTION=str(connection), XIAOKAI_COMMAND_TEST_QUESTIONS='复制个CN10出来，复制件Value改CHAT-CLONE，放到我点的空白处，再旋转90度、上下镜像，位号改CN99', XIAOKAI_COMMAND_TEST_LOG=str(log))
        subprocess.run(['C:/orcad/Cadence/SPB_17.4/tcltk/bin/tclsh.exe', str(target)], check=True, timeout=45, env=env)
        assert not errors, errors
        assert len(seen) == 7, (len(seen), log.read_text('utf-8'))
        transcript = log.read_text('utf-8')
        assert 'dummy-parts-key' not in transcript
        assert '已复制 1 个器件：CN11' in transcript and '已将器件位号依次改为CN99' in transcript
        print('PASS: one natural-language request, seven mocked model decisions, six native tools, no repeated copy, source untouched, local dummy credential only')
finally:
    server.shutdown()
