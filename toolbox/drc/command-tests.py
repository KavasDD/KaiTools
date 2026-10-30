"""Model protocol tests against localhost only; no real credentials or CAD process."""
import base64
import json
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
EXE = ROOT / 'test-output/ai-bridge-tests.exe'
pdf_dlls = sorted((ROOT/'vendor/pdf-runtime').glob('*.dll'))
subprocess.run(['C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe', '/nologo', '/target:exe', '/define:AI_TEST', '/codepage:65001',
    *('/r:'+name for name in ['System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Security.dll','System.Web.Extensions.dll']),
    *('/r:'+str(path) for path in pdf_dlls), *('/resource:'+str(path)+',pdf.'+path.name for path in pdf_dlls), '/out:'+str(EXE),
    *(str(ROOT/name) for name in ['AiBridge.cs','Datasheets.cs','PanelJobs.cs','AiDiagnostics.cs','CommandAssistant.cs'])], check=True)
answer = {}
status = 200

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        assert self.path == '/v1/chat/completions'
        assert self.headers['Authorization'] == 'Bearer dummy-command-test'
        prompt = json.loads(request['messages'][1]['content'])
        assert 'request_id' in prompt and 'current' in prompt
        body = json.dumps({'choices': [{'finish_reason': 'stop', 'message': {'content': json.dumps(answer)}}]}).encode()
        self.send_response(status); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
request_id = '0123456789abcdef0123456789abcdef'
with tempfile.TemporaryDirectory(prefix='xiaokai-command-tests-') as temp:
    temp = Path(temp)
    config = temp/'config.json'; source = temp/'source.json'; output = temp/'output.tsv'; cancel = temp/'cancel'
    config.write_text(json.dumps({'Endpoint': f'http://127.0.0.1:{server.server_port}/v1', 'Model': 'fixture', 'Secret': 'dummy-command-test'}), 'utf-8')
    source.write_text(json.dumps({'request_id': request_id, 'question': '放置4条带网络名的导线到空白处', 'context': {'parts': [{'index': i, 'ref': f'R{i+1}'} for i in range(4)], 'wires': [{'index':i,'names':['XKA_111111111111_'+str(i+1)]} for i in range(6)], 'labels':[{'index':i,'kind':'offpage','name':'MCU_MDI'+str(i)} for i in range(3)]}}), 'utf-8')
    def run(row, platform='orcad', ok=True):
        global answer
        answer = dict(request_id=request_id, message='执行测试', **row)
        subprocess.run([str(EXE), '--command-fixture', platform, str(source), str(output), str(cancel), str(config)], check=True, timeout=10)
        result = output.read_text('utf-8')
        assert result.startswith(('ACTION' if row['action'] not in ('reply', 'clarify') else 'SAY') if ok else 'ERROR'), result
        assert 'dummy-command-test' not in result
        return result.split('\t')
    part_actions = [
        {'action':'copy_parts','target_indices':[0]},
        {'action':'copy_parts','target_indices':[0,1],'count':2,'layout':'grid','spacing_mil':300,'near_part_index':0,'placement':'pick','references':['R20','R21','R22','R23']},
        {'action':'move_parts','target_indices':[0,1],'dx_mil':-500,'dy_mil':200},
        {'action':'move_parts','target_indices':[0],'near_part_index':2,'direction':'below'},
        {'action':'rotate_parts','target_indices':[0,1],'angle_degrees':-90},
        {'action':'mirror_parts','target_indices':[0],'axis':'vertical'},
        {'action':'align_parts','target_indices':[0,1],'alignment':'center_x'},
        {'action':'distribute_parts','target_indices':[0,1,2],'axis':'horizontal','gap_mil':300},
        {'action':'set_part_property','target_indices':[0,1],'property':'PCB Footprint','values':['R0402','R0603']},
        {'action':'set_part_property','target_indices':[0,1],'property':'Value','values':['10K']},
        {'action':'rename_parts','target_indices':[0,1],'references':['R20','R21']}]
    for row in part_actions:
        fields = run(row)
        options = json.loads(base64.b64decode(fields[7]))
        assert options['target_indices'] == row['target_indices']
        for key, value in row.items():
            if key != 'action': assert options[key] == value, (key, options)
        run(row, 'allegro', ok=False)
    invalid_parts = [
        {'action':'copy_parts','count':17}, {'action':'copy_parts','count':False},
        {'action':'copy_parts','count':9,'target_indices':[0,1,2,3]},
        {'action':'copy_parts','references':['R1','R2']},
        {'action':'copy_parts','references':['[exit]']},
        {'action':'copy_parts','placement':'eval'},
        {'action':'copy_parts','near_part_index':4},
        {'action':'copy_parts','target_indices':[0,0]},
        {'action':'copy_parts','target_indices':[0.5]},
        {'action':'copy_parts','target_indices':[4]},
        {'action':'copy_parts','target_indices':[]},
        {'action':'move_parts','dx_mil':200},
        {'action':'move_parts','dx_mil':0,'dy_mil':0},
        {'action':'move_parts','dx_mil':10001,'dy_mil':0},
        {'action':'move_parts','dx_mil':100,'dy_mil':0,'placement':'blank'},
        {'action':'move_parts','near_part_index':0},
        {'action':'rotate_parts','angle_degrees':45},
        {'action':'rotate_parts','angle_degrees':0},
        {'action':'mirror_parts','axis':'eval'},
        {'action':'align_parts','alignment':'top'},
        {'action':'distribute_parts','target_indices':[0,1],'axis':'horizontal'},
        {'action':'set_part_property','property':'Reference','values':['R20']},
        {'action':'set_part_property','property':'Value','values':['']},
        {'action':'set_part_property','property':'Value','values':['a\nb']},
        {'action':'set_part_property','property':'Value','values':[20]},
        {'action':'set_part_property','property':'Value','values':['x'*257]},
        {'action':'set_part_property','property':'Value','values':[]},
        {'action':'rename_parts','references':['R?']},
        {'action':'rename_parts','target_indices':[0,1],'references':['R20','r20']}]
    for row in invalid_parts:
        row = dict(target_indices=[0], **row) if 'target_indices' not in row else row
        run(row, ok=False)
    run({'action':'copy_parts'}, ok=False)
    fields = run({'action': 'place_net_wires', 'count': 4, 'names': []})
    assert fields[3] == '4'
    fields = run({'action': 'place_net_wires', 'count': 2, 'names': ['SPI_CLK', 'SPI_MOSI']})
    assert base64.b64decode(fields[4]).decode() == 'SPI_CLK\nSPI_MOSI'
    fields = run({'action':'place_net_wires','count':2,'names':[],'near_index':1,'direction':'right','spacing_mil':800,'clearance_mil':1200})
    geometry=json.loads(base64.b64decode(fields[7]))
    assert geometry['near_index']==1 and geometry['spacing_mil']==800 and geometry['clearance_mil']==1200
    fields = run({'action':'move_wires','target_indices':[4,5],'near_index':1,'direction':'right','spacing_mil':1200})
    assert json.loads(base64.b64decode(fields[7]))['target_indices']==[4,5]
    fields = run({'action':'add_offpage_inputs','target_indices':list(range(6))})
    assert json.loads(base64.b64decode(fields[7]))['target_indices']==list(range(6))
    for direction in ['input','output']:
        fields = run({'action':'set_offpage_direction','target_indices':[4,5],'signal_type':direction})
        assert json.loads(base64.b64decode(fields[7]))['signal_type']==direction
    run({'action':'set_offpage_direction','target_indices':[4,5]},ok=False)
    run({'action':'set_offpage_direction','target_indices':[4,5],'signal_type':'eval'},ok=False)
    run({'action':'set_offpage_direction','target_indices':[4,5],'signal_type':'input'},'allegro',ok=False)
    fields = run({'action':'rename_wires','target_indices':[4,5],'names':['P1','P2']})
    assert base64.b64decode(fields[4]).decode()=='P1\nP2'
    fields = run({'action':'rename_net_labels','label_indices':[0,1,2],'names':['MCU_M0','MCU_M1','MCU_M2']})
    assert json.loads(base64.b64decode(fields[7])) == {'label_indices':[0,1,2]}
    assert base64.b64decode(fields[4]).decode()=='MCU_M0\nMCU_M1\nMCU_M2'
    for row in [
        {'action':'rename_net_labels','label_indices':[3],'names':['P1']},
        {'action':'rename_net_labels','label_indices':[-1],'names':['P1']},
        {'action':'rename_net_labels','label_indices':[0.5],'names':['P1']},
        {'action':'rename_net_labels','label_indices':[0,0],'names':['P1','P2']},
        {'action':'rename_net_labels','label_indices':[0,1],'names':['P1']},
        {'action':'rename_net_labels','label_indices':[],'names':[]},
        {'action':'rename_net_labels','label_indices':[0],'names':['[exit]']},
        {'action':'rename_net_labels','names':['P1']}]:
        run(row,ok=False)
    run({'action':'rename_net_labels','label_indices':[0],'names':['P1']},'allegro',ok=False)
    fields = run({'action':'move_wires','target_indices':[4,5],'spacing_factor':0.5})
    assert json.loads(base64.b64decode(fields[7]))['spacing_factor']==0.5
    fields = run({'action':'place_net_wires','count':2,'placement':'pick'})
    assert json.loads(base64.b64decode(fields[7]))['placement']=='pick'
    fields = run({'action':'place_net_wires','count':2,'names':['P1','P2'],'inputs':True})
    assert json.loads(base64.b64decode(fields[7]))['inputs'] is True
    run({'action': 'place_text', 'text': '检查电源'})
    fields = run({'action':'set_part_value','index':0,'text':'con-200'})
    assert base64.b64decode(fields[5]).decode()=='con-200'
    run({'action':'set_part_value','index':0,'text':'con-200'},'allegro',ok=False)
    run({'action':'set_part_value','index':0,'text':''},ok=False)
    run({'action':'set_part_value','index':-1,'text':'con-200'},ok=False)
    run({'action': 'locate', 'index': 0}, 'allegro')
    run({'action': 'open_tool', 'tool': 'grid'}, 'allegro')
    run({'action': 'clarify'})
    run({'action': 'reply'})
    for row in [
        {'action': 'eval', 'text': 'exit'},
        {'action': 'place_net_wires', 'count': 100, 'names': []},
        {'action': 'place_net_wires', 'count': 1.5, 'names': []},
        {'action': 'place_net_wires', 'count': 2, 'names': ['A']},
        {'action': 'place_net_wires', 'count': 2, 'names': ['A', 'a']},
        {'action': 'place_net_wires', 'count': 1, 'names': ['[exit]']},
        {'action': 'place_text', 'text': 'x'*81},
        {'action': 'place_text', 'text': 'a\nb'},
        {'action': 'locate', 'index': -1},
        {'action': 'open_tool', 'tool': 'exit'}]:
        run(row, ok=False)
    for row in [
        {'action':'place_net_wires','count':2,'names':[],'near_index':6},
        {'action':'place_net_wires','count':2,'names':[],'direction':'[exit]'},
        {'action':'place_net_wires','count':2,'names':[],'spacing_mil':0},
        {'action':'place_net_wires','count':2,'names':[],'clearance_mil':1.5},
        {'action':'move_wires','target_indices':[1],'near_index':1},
        {'action':'move_wires','target_indices':[1,1]},
        {'action':'add_offpage_inputs','target_indices':[]},
        {'action':'add_offpage_inputs','target_indices':[6]},
        {'action':'add_offpage_inputs','target_indices':[1.5]},
        {'action':'add_offpage_inputs'}]:
        run(row,ok=False)
    for row in [
        {'action':'rename_wires','target_indices':[4,5],'names':['P1']},
        {'action':'rename_wires','target_indices':[4,5],'names':['P1','p1']},
        {'action':'rename_wires','target_indices':[4,5],'names':['P1','[exit]']},
        {'action':'rename_wires','target_indices':[4,5]},
        {'action':'move_wires','target_indices':[4,5],'spacing_factor':'0.5'},
        {'action':'move_wires','target_indices':[4,5],'spacing_factor':0},
        {'action':'move_wires','target_indices':[4,5],'spacing_factor':10},
        {'action':'place_net_wires','count':2,'placement':'[exit]'}]:
        run(row,ok=False)
    run({'action':'place_net_wires','count':2,'inputs':'true'},ok=False)
    run({'action':'rename_wires','target_indices':[0],'names':['P1']}, 'allegro',ok=False)
    run({'action':'move_wires','target_indices':[0]}, 'allegro',ok=False)
    run({'action':'add_offpage_inputs','target_indices':[0]}, 'allegro',ok=False)
    run({'action': 'place_net_wires', 'count': 4, 'names': []}, 'allegro', ok=False)
    answer = {'request_id': 'stale', 'action': 'reply', 'message': '旧结果'}
    subprocess.run([str(EXE), '--command-fixture', 'orcad', str(source), str(output), str(cancel), str(config)], check=True, timeout=10)
    assert output.read_text('utf-8').startswith('ERROR')
    cancel.write_text('cancel')
    run({'action': 'locate', 'index': 0}, ok=False)
server.shutdown()
print('PASS: command allowlist, both platforms, wire names/count, text/index limits, unsupported/malicious output, stale batch, cancellation, no credential disclosure')
