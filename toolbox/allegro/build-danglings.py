"""Build a namespaced, combined check/repair adapter; retain the original file."""
from hashlib import sha256
from pathlib import Path
import re

root = Path(__file__).resolve().parent
original = (root / "originals" / "quick_danglings.il").read_bytes()
assert sha256(original).hexdigest() == "4a3c0b5f13b04e006c46ce56f36c674e75e9a8cbcf6fbbec93f9eb367e45169a"
# The header contains damaged legacy comment bytes. Executable code is ASCII.
start = original.index(b'axlCmdRegister(')
source = original[start:].decode("ascii")
source, count = re.subn(r'^axlCmdRegister\([^\n]+\n', '', source, count=1, flags=re.M)
assert count == 1
for old, new in {
    "quick_danglings": "xkDdoRun",
    "ps_DanglingForm_action": "xkDdoFormAction",
    "ps_ddoCheck": "xkDdoScan",
    "psmddo_HELPPAGE": "xkDdoHelpPage",
}.items():
    source = re.sub(r'\b' + old + r'\b', new, source)

def replace_once(old, new):
    global source
    assert source.count(old) == 1, old
    source = source.replace(old, new, 1)

replace_once('axlFormDisplay( ps_DanglingForm )', '''xkDdoShowPage(ps_DanglingForm 'lines)
          axlFormDisplay( ps_DanglingForm )
          xkDdoActiveForm = ps_DanglingForm''')
# The original island Delete branch refers to a misspelled form variable.
# Correct only these two references in the adapter; leave the original intact.
assert source.count('nv_DanglingForm1') == 2
source = source.replace('nv_DanglingForm1', 'ps_DanglingForm1')
source = source.replace('ps_DanglingForm.form', 'xkDanglingChinese.form')
# Allow the native title-bar close button instead of disabling system close.
replace_once('          axlUIWDisableQuit(ps_DanglingForm)', '')
# Place results inside their tabs so the tab body is useful content.
form = '''FILE_TYPE=FORM_DEFN VERSION=2
FORM
FIXED
PORT 80 54
HEADER "D1：悬空线、过孔与孤岛检查处理"
TILE
TABSET tset
OPTIONS tabsetDispatch
FLOC 2 1
FSIZE 76 46
'''
for label, page, info, field in (
    ('悬空线', 'linesPage', 'ddoLineInfo', 'ddoLineList'),
    ('悬空过孔', 'viasPage', 'ddoViaInfo', 'ddoViaList'),
    ('孤岛', 'shapesPage', 'ddoShapeInfo', 'ddoShapeList'),
):
    form += f'TAB "{label}" {page}\nTEXT "数量："\nTLOC 1 1\nENDTEXT\n'
    form += f'TEXT\nTLOC 11 1\nINFO {info} 10\nENDTEXT\n'
    form += f'FIELD {field}\nFLOC 1 4\nLIST "" 0 0\nFSIZE 74 39\nOPTIONS multiselect\nENDFIELD\nENDTAB\n'
form += 'ENDTABSET\n'
for field, label, x in (
    ('ddoRefresh', '刷新', 3), ('ddoDelete', '删除', 18),
):
    form += f'FIELD {field}\nFLOC {x} 49\nMENUBUTTON "{label}" 12 3\nENDFIELD\n'
form += 'FLEXMODE edgegravity\nFLEX tset 0 0 1 1\n'
for field in ('ddoLineList', 'ddoViaList', 'ddoShapeList'):
    form += f'FLEX {field} 0 0 1 1\n'
form += 'FLEX ddoRefresh 0 1 0 0\n'
for field in ('ddoDelete',):
    form += f'FLEX {field} 0 1 0 0\n'
form += 'ENDTILE\nENDFORM\n'
escaped_form = form.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
a = source.index('          fprintf( ps_DanglingForm_Port "FILE_TYPE=FORM_DEFN')
b = source.index('          close( ps_DanglingForm_Port )', a)
source = source[:a] + f'          fprintf(ps_DanglingForm_Port "{escaped_form}")\n' + source[b:]
replace_once("'xkDdoFormAction t)", "'xkDdoUiAction t)")
# curField is maintained by Allegro. Pass a dispatch key explicitly instead
# of trying to overwrite it when a shared button invokes an original action.
replace_once('procedure( xkDdoFormAction( ps_DanglingForm1 )',
             'procedure( xkDdoFormAction( ps_DanglingForm1 @optional actionField )')
replace_once('case( ps_DanglingForm1->curField',
             'case( or(actionField ps_DanglingForm1->curField)')

# Translate display strings only; preserve field identifiers and PCB names.
translations = {
    'xkDdoRun from www.eda365.com': '小开工具箱：检查悬空线、过孔和孤岛',
    'Tool from www.eda365.com': '选择列表项定位，支持多选处理',
    'Refresh': '刷新', 'Help': '帮助', 'Close': '关闭',
    'Delete': '删除', 'Change Net': '修改网络',
    'Dangling Lines': '悬空线', 'Dangling Line:': '悬空线数量：',
    'Dangling Vias': '悬空过孔', 'Dangling Vias:': '悬空过孔数量：',
    'Island Shapes': '孤岛', 'Island Shapes:': '孤岛数量：',
    'E- %d Dangling Lines, check Dangling Lines Tab': '发现 %d 条悬空线，请查看悬空线页',
    'E- %d Dangling Via, check Dangling Vias Tab': '发现 %d 个悬空过孔，请查看悬空过孔页',
    'E- %d Island Shape, check Island Shapes Tab': '发现 %d 个孤岛，请查看孤岛页',
    'Select Dangling, Island Line/Via/Shape...': '选择列表项定位，选中后可删除；右上角 × 关闭窗口。',
    'I- No dangling, island line/via/shape problems': '未发现悬空线、过孔或孤岛。',
    'I- No Dangling, Island Lines/Vias/Shapes': '未发现悬空线、过孔或孤岛。',
    'Can not find the cline, find it manually...': '未找到对应走线，请手动定位。',
    'I- Dangling Line was deleted': '已删除所选悬空线。',
    'I- Dangling Via was deleted': '已删除所选悬空过孔。',
    'I- Island Shape was deleted': '已删除所选孤岛。',
    'E- Pick a item from the list before cilck on Delete button': '请先在列表中选择要删除的对象。',
    'R- if delete shape on this form is too slow, please use Shape->Delete Islands to delete all island shape and use this tool to double confirm': '若孤岛删除较慢，可使用形状菜单的删除孤岛功能，再刷新复查。',
    'Done, Please update DRC and refresh shapes': '处理完成，请更新 DRC 并刷新铜皮。',
    'I- Select a net by click in the design': '请在板图中点击选择目标网络。',
    'I- Change via net from %s to %s': '过孔网络已从 %s 改为 %s',
    'I- Change via net from nil to %s': '无网络过孔已改为 %s',
    'I- Dangling Via net was changed': '已修改过孔网络。',
    'E- Dummy net was selected, no changes': '未选到有效网络，没有修改。',
    'E- Pick a item from the list before cilck on Assign Net button': '请先在列表中选择要修改网络的过孔。',
}
for old, new in translations.items():
    # Match complete strings, avoiding identifiers such as ddoRefresh.
    for quote in ('"', '\\"'):
        source = source.replace(quote + old + quote, quote + new + quote)
source += '''
procedure(xkDdoShowPage(form page)
  form->XkPage = page
)
procedure(xkDdoUiAction(form)
  let((field)
    field = form->curField
    cond(
      (field == "tset"
        cond(
          (member(form->curValue '("linesPage" "悬空线")) xkDdoShowPage(form 'lines))
          (member(form->curValue '("viasPage" "悬空过孔")) xkDdoShowPage(form 'vias))
          (member(form->curValue '("shapesPage" "孤岛")) xkDdoShowPage(form 'shapes))
        )
      )
      (field == "ddoDelete"
        xkDdoFormAction(form case(form->XkPage
          (lines "ddoLinesDel") (vias "ddoViasDel") (shapes "ddoShapesDel")))
      )
      (member(field '("done" "cancel")) xkDdoFormAction(form "ddoClose"))
      (t xkDdoFormAction(form))
    )
  )
)
procedure(xkDdoCheckEntry() xkDdoRun())
axlCmdRegister("xk_dangling_check" 'xkDdoCheckEntry ?cmdType "general")
axlCmdRegister("xk_dangling_vias" 'x_change_via_net)
axlCmdRegister("xk_via_change_net" 'x_change_via_net)
'''
source = '; Generated by build-danglings.py. Original SHA-256 verified.\n' + source
# Cadence remembers layout by form name. Give changed definitions a fresh key.
layout_key = sha256(source.encode('utf-8')).hexdigest()[:12]
source = source.replace('xkDanglingChinese.form', f'xkDangling_{layout_key}.form')
encoded = ''.join(c if ord(c) < 128 else ''.join(f'\\{b:03o}' for b in c.encode('gbk')) for c in source)
(root / 'skill' / 'xiaokaiDanglings.il').write_bytes(encoded.encode('ascii'))
