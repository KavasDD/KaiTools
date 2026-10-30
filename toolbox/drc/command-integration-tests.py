"""Real WinForms chat -> local API -> Tcl pipe -> native Dbo on a sample copy."""
import json
import os
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
EXE = ROOT/'test-output/command-integration.exe'
DLLS = sorted((ROOT/'vendor/pdf-runtime').glob('*.dll'))
subprocess.run(['C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe', '/nologo', '/target:winexe', '/define:AI_TEST', '/codepage:65001',
    *('/r:'+p for p in ['System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Security.dll','System.Web.Extensions.dll']),
    *('/r:'+str(p) for p in DLLS), *('/resource:'+str(p)+',pdf.'+p.name for p in DLLS), '/out:'+str(EXE),
    *(str(ROOT/p) for p in ['AiBridge.cs','Datasheets.cs','PanelJobs.cs','AiDiagnostics.cs','CommandAssistant.cs'])], check=True)

seen=[]
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        payload=json.loads(body['messages'][1]['content']); seen.append(payload)
        assert self.headers['Authorization']=='Bearer dummy-integration-key'
        current=json.loads(payload['current'])
        wires=current['wires']; generated=[w for w in wires if w['tool_generated']]
        assert 'move_wires' in body['messages'][0]['content'] and 'add_offpage_inputs' in body['messages'][0]['content']
        answer={'request_id':payload['request_id'],'message':'执行测试'}
        turn=sum(not p['tool_results'] for p in seen)
        done=payload['tool_results']
        if done and turn != 7:
            assert done[-1]['call']['action'] in ['place_net_wires','rename_wires','move_wires','add_offpage_inputs','set_offpage_direction']
            assert '已' in done[-1]['result'] and len(done)==1
            if turn in (8,9):
                recent=[w for w in wires if w['recent']]
                facing='left' if turn==8 else 'right'
                assert len(recent)==2 and all(w['offpage_connectors'][0]['facing']==facing for w in recent)
            answer.update(action='reply',message='已核对实际结果，本次要求已完成。')
        elif turn==1:
            answer.update(action='place_net_wires',count=4,names=[])
        elif turn==2:
            assert len(generated)==4 and generated[0]['names'][0] in payload['history']
            answer.update(action='place_net_wires',count=2,names=[],near_index=generated[1]['index'],direction='right',spacing_mil=800,clearance_mil=800)
        elif turn==3:
            assert len(generated)==6 and '行间距800mil' in payload['history']
            recent=[w for w in wires if w['recent']]
            assert len(recent)==2
            answer.update(action='rename_wires',target_indices=[w['index'] for w in recent],names=['P1','P2'])
        elif turn==4:
            recent=[w for w in wires if w['recent']]
            assert len(recent)==2 and [w['names'][0] for w in recent]==['P1','P2']
            answer.update(action='move_wires',target_indices=[w['index'] for w in recent],spacing_factor=0.5)
        elif turn==5:
            assert '已调整 2 条独立导线' in payload['history']
            targets=[w['index'] for w in wires if w['tool_generated'] or w['names']==['P1'] or w['names']==['P2']]
            assert len(targets)==6
            answer.update(action='add_offpage_inputs',target_indices=targets)
        elif turn==6:
            answer.update(action='place_net_wires',count=2,placement='pick',names=['CLICK1','CLICK2'],inputs=True)
        elif turn in (8,9):
            recent=[w for w in wires if w['recent']]
            facing='right' if turn==8 else 'left'
            assert len(recent)==2 and all(w['offpage_connectors'][0]['facing']==facing for w in recent)
            answer.update(action='set_offpage_direction',target_indices=[w['index'] for w in recent],signal_type='output' if turn==8 else 'input')
        else:
            assert turn==7
            recent=[w for w in wires if w['recent']]
            if len(done)==0:
                answer.update(action='place_net_wires',count=2,names=[])
            elif len(done)==1:
                assert done[-1]['call']['action']=='place_net_wires' and len(recent)==2
                answer.update(action='rename_wires',target_indices=[w['index'] for w in recent],names=['SEQ_A','SEQ_B'])
            elif len(done)==2:
                assert [w['names'][0] for w in recent]==['SEQ_A','SEQ_B']
                assert done[-1]['call']['names']==['SEQ_A','SEQ_B']
                answer.update(action='move_wires',target_indices=[w['index'] for w in recent],spacing_factor=0.5)
            elif len(done)==3:
                assert done[-1]['call']['action']=='move_wires' and '行间距100mil' in done[-1]['result']
                answer.update(action='add_offpage_inputs',target_indices=[w['index'] for w in recent])
            else:
                assert len(done)==4 and done[-1]['call']['action']=='add_offpage_inputs'
                answer.update(action='reply',message='已完成新增、分别改名、缩小间距和输入连接符，逐步结果已核对。')
        response=json.dumps({'choices':[{'finish_reason':'stop','message':{'content':json.dumps(answer)}}]}).encode()
        self.send_response(200);self.send_header('Content-Length',str(len(response)));self.end_headers();self.wfile.write(response)

server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='xiaokai-command-e2e-') as temp:
        folder=Path(temp); config=folder/'fixture.json'; connection=folder/'connection.json'; chatlog=folder/'chat.txt'
        config.write_text(json.dumps({'Endpoint':f'http://127.0.0.1:{server.server_port}/v1','Model':'fixture','Secret':'dummy-integration-key'}),'utf-8')
        subprocess.run([str(EXE),'--roundtrip',str(config),str(connection),str(folder/'result')],check=True,timeout=10)
        assert (folder/'result').read_text()=='PASS'
        script=folder/'integration.tcl'
        tcl=r'''
fconfigure stdout -encoding utf-8
try {
    load {C:/orcad/Cadence/SPB_17.4/tools/bin/orDb_Dll_Tcl64.dll} DboTclWriteBasic
    source {PLUGIN}
    set fixture {FIXTURE}
    file copy {C:/orcad/Cadence/SPB_17.4/tools/capture/samples/PCB-Layout/FullAdder/FULLADD.DSN} $fixture
    set session [DboTclHelper_sCreateSession]; set s [DboState]
    set c [DboTclHelper_sMakeCString $fixture]; set design [$session GetDesignAndSchematics $c $s]; DboTclHelper_sDeleteCString $c
    set page [::xiaokai::drc::reviewPage $design FULLADD FULLADD]
    set a [DboTclHelper_sMakeCPoint 60 60]; set b [DboTclHelper_sMakeCPoint 70 70]
    try {
        set entry [$page NewBusEntry $s $a $b]
        if {$entry eq "NULL" || ![$s OK]} {error "Bus entry fixture creation failed"}
    } finally {DboTclHelper_sDeleteCPoint $a; DboTclHelper_sDeleteCPoint $b}
    proc ::xiaokai::drc::activeDesign {} {return $::design}
    proc GetActivePage {} {return $::page}
    rename ::xiaokai::drc::aiHelper ::xiaokai::drc::savedHelper
    proc ::xiaokai::drc::aiHelper {} {return {HELPER}}
    set before [$page GetWireCount $s]
    set portsBefore [$page GetOffPageConnectorCount $s]
    ::xiaokai::drc::commandOpen
    proc GetLastMouseClickPointOnPage {} {return $::testClick}
    proc emulateNativeClick {} {
        if {[llength $::xiaokai::drc::commandPick]} {
            set context [dict get $::xiaokai::drc::commandPick context]
            lassign [::xiaokai::drc::commandSpace $::page 160 80] x y
            set ::testClick [list [expr {$x/double([$::page GetPhysicalGranularity])}] [expr {($y+20)/double([$::page GetPhysicalGranularity])}]]
            ::xiaokai::drc::commandPickApply
        }
        if {$::xiaokai::drc::commandChannel ne ""} {after 100 emulateNativeClick}
    }
    after 100 emulateNativeClick
    set deadline [expr {[clock milliseconds]+25000}]
    while {$::xiaokai::drc::commandChannel ne ""} {
        update; after 20
        if {[clock milliseconds]>$deadline} {error "Chat/native pipe timeout"}
    }
    if {[$page GetWireCount $s]!=$before+10} {error "Native wire count did not increase by ten"}
    if {[$page GetOffPageConnectorCount $s]!=$portsBefore+10} {error "Native input offpage count did not increase by ten"}
    set finalRows [::xiaokai::drc::commandWires $page]
    set pair {}; foreach row $finalRows {if {[dict get $row name] in {SEQ_A SEQ_B}} {lappend pair $row}}
    if {[llength $pair]!=2} {error "Agent pair names did not persist"}
    if {abs([lindex [dict get [lindex $pair 0] points] 0 1]-[lindex [dict get [lindex $pair 1] points] 0 1])!=10} {error "Agent spacing not adjusted"}
    foreach row $pair {if {[llength [::xiaokai::drc::commandWireAttachments $row $s]]!=1} {error "Agent input connector missing"}}
    puts "PASS: model tool loop -> fresh native context after every step, four-step single request, relative place/rename/spacing/offpages/pick"
} on error {msg options} {puts stderr [dict get $options -errorinfo]; exit 1}
exit 0
'''
        for name,value in {'PLUGIN':ROOT.parent.parent/'autoload/drctoolMenu.tcl','FIXTURE':folder/'test.dsn','HELPER':EXE}.items():
            tcl=tcl.replace(name,str(value).replace('\\','/'))
        script.write_text(tcl,'utf-8')
        questions=['放置4条带网名导线','在刚放置的第二条导线右侧再放2条，行间距和净空800mil','这两个网络名分别改成P1和P2','挪近一点','给刚才这6条线都加上对应的输入型页间连接符','再做两条带网络号线到我鼠标上，叫CLICK1和CLICK2，带输入页间连接符','再来一对线，随后分别改成SEQ_A和SEQ_B，间距缩小一半，最后补齐各自的输入连接符。','这两个页间连接符改成输出方向','你这是输出型页间连接符，我要的是输入，改回来']
        env=dict(os.environ,XIAOKAI_AI_TEST_CONNECTION=str(connection),XIAOKAI_COMMAND_TEST_QUESTIONS='\n'.join(questions),XIAOKAI_COMMAND_TEST_LOG=str(chatlog))
        subprocess.run(['C:/orcad/Cadence/SPB_17.4/tcltk/bin/tclsh.exe',str(script)],check=True,timeout=40,env=env)
        log=chatlog.read_text('utf-8')
        assert '已在当前页空白处放置 2 条' in log and 'dummy-integration-key' not in log
        assert '已调整 2 条独立导线' in log and '已为 6 条现有导线添加同网名的输入型页间连接符' in log
        assert '改名为P1、P2' in log and '请在当前原理图上单击' in log
        assert len(seen)==21 and 'FULLADD' in seen[0]['current']
        assert '调整为输入型（箭头向右）' in log and '调整为输出型（箭头向左）' in log
        assert 'AI 调用' in log and '执行结果' in log and '逐步结果已核对' in log
        print('PASS: nine user requests, 21 model decisions, 12 native tool calls, input/output correction using actual facing metadata, single-request four-tool composition, fresh context/results, recent identity, picked geometry, credential isolation')
finally:
    server.shutdown()
