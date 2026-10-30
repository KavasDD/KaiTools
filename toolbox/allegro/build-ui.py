"""Encode the Chinese UI for Allegro 17.4 on Chinese Windows."""
from pathlib import Path
from hashlib import sha256
import re

root = Path(__file__).resolve().parent
view_hashes = {
    "Find_Component.il": "8345edbf070c3891d2196b89dbcc0b9358d25604a9fe74c805c94059906342a6",
    "Find_DRC.il": "784c4ba4b4bc07d8246d474a29fbfc8c95dbcad4d2cbcf2914436ad46cf4ab4b",
    "quick_grids.il": "b7cc14b8f3fff27b62aad8705f611cc935a6e9784f8e5073b72716449e23e533",
    "quick_display.il": "27d4add90b8d79f67dad3d18ff49e3233d2ec92d09408928ebe54f2de9a3da52",
    "conv.il": "34bf3c02862eb8c9ed700466091756a6bc6b1eaff9ca7caa08d92a68e208be0b",
    "highlight_padstack.il": "8c3f96fa9d058479711b2e7ce9d415bfd474420af01f00dd322d3e1974b03c5d",
    "show_library.il": "68c4be0d2175ed51f5a412a95da7a0e086907e1a73d975762b7fdd6b164e439e",
    "show_height.il": "ba192662def349bd6d1e176b84a034e4cd59b54e5335d8595f61a9c2edf40298",
}
for name, expected in view_hashes.items():
    original = (root / "originals" / name).read_bytes()
    assert sha256(original).hexdigest() == expected, name
    adapted = original
    if name == "Find_DRC.il":
        # Allegro normalizes the reserved Done control to lowercase done.
        adapted = adapted.replace(b'FIELD Done', b'FIELD done').replace(b'("Done"', b'(("done" "cancel")')
        adapted = adapted.replace(b'shell("rm Find_DRC_Form.form")', b'when(isFile("Find_DRC_Form.form") deleteFile("Find_DRC_Form.form"))')
        adapted = adapted.replace(b'shell("rm List_DRC_From.form")', b'when(isFile("List_DRC_From.form") deleteFile("List_DRC_From.form"))')
        # Ignore empty/sentinel list events; only real DRC rows have coordinates.
        adapted = adapted.replace(b'DRC=List_DRC_From->curValue',
            b'DRC=List_DRC_From->curValue\n     when(stringp(DRC) && member(DRC Error_List) && length(parseString(DRC ",")) >= 3')
        adapted = adapted.replace(b'); end "DRC_List"', b')\n    ); end "DRC_List"')
        adapted = adapted.replace(b'PORT 27 5', b'PORT 60 12')
        adapted = adapted.replace(b'ENUMSET 20', b'ENUMSET 48')
        adapted = adapted.replace(b'PORT 80 10', b'PORT 130 48')
        adapted = adapted.replace(b'LIST \\\"\\\" 77 6', b'LIST \\\"\\\" 124 18')
        for xpos in (6, 30, 54):
            adapted = adapted.replace(f'FLOC {xpos} 16'.encode(), f'FLOC {xpos} 40'.encode())
        adapted = adapted.replace(b'fprintf(List_DRC_From "ENDTILE',
            b'fprintf(List_DRC_From "FLEXMODE edgegravity\\nFLEX DRC_List 0 0 1 1\\n")\n  fprintf(List_DRC_From "ENDTILE')
    elif name == "highlight_padstack.il":
        adapted = adapted.replace(b'PORT 27 45', b'PORT 64 65')
        adapted = adapted.replace(b' 24 9', b' 58 15').replace(b' 24 4', b' 58 9')
        adapted = adapted.replace(b'FLOC 2 22', b'FLOC 2 38').replace(b'TLOC 2 20', b'TLOC 2 36')
        adapted = adapted.replace(b'FLOC 12 30', b'FLOC 28 59')
        adapted = adapted.replace(b'MENUBUTTON \\"Done\\" 2 3', b'MENUBUTTON \\"Done\\" 12 3')
        adapted = adapted.replace(b'fprintf(hps_formd "ENDTILE',
            b'fprintf(hps_formd "FLEXMODE edgegravity\\nFLEX padstacklist 0 0 1 0.65\\nFLEX drillholelist 0 0.65 1 0.35\\nFLEX Done 0.5 1 0 0\\n")\n  fprintf(hps_formd "ENDTILE')
    (root / "skill" / name).write_bytes(adapted)
via_original = (root / "originals" / "x_change_via_net.il").read_bytes()
assert sha256(via_original).hexdigest() == "00b329799be936189254ad212fab4288b92790abac7efb76972095dbf3751641"
# Fix the original empty-selection guard only; WHEN does not take THEN.
assert via_original.count(b'when( all == nil then') == 1
(root / "skill" / "x_change_via_net.il").write_bytes(
    via_original.replace(b'when( all == nil then', b'when( all == nil', 1)
)

# B tools: retain immutable upstream snapshots and adapt installation copies.
import json

def isolate_overlap_symbols(data):
    # D8 stays open while other tools run. Its original globals (cnt, layer,
    # text_pad, form, etc.) must not be overwritten by B1/B6/B7 or old SKILLs.
    text = data.decode('gbk')
    protected = r'"(?:\\.|[^"\\])*"|;[^\n]*|/\*[\s\S]*?\*/'
    mask = re.sub(protected, lambda m: ' ' * len(m[0]), text)
    names = set(re.findall(r'(?<![\w>])([A-Za-z_]\w*)\s*=(?!=)', mask))
    names.update(re.findall(r'\bdefun\s*\(?\s*(\w+)', mask))
    names.update(re.findall(r'\bforeach\s*\(\s*(\w+)', mask))
    tokens = re.compile(protected + r'|(?<![\w>])\b[A-Za-z_]\w*\b')
    return tokens.sub(lambda m: 'xkB5_' + m[0] if m[0] in names else m[0], text).encode('gbk')

b_hashes = json.loads((root / "originals/b-tools-hashes.json").read_text(encoding="utf-8"))
for name, expected in b_hashes.items():
    data = (root / "originals" / name).read_bytes()
    assert sha256(data).hexdigest() == expected, name
    if name == "check_dir.il":
        continue  # B4 removed from the selected collection; snapshot retained.
    if name == "quick_textset.il":
        assert data.count(b"*(1.0/du)") == 5
        data = data.replace(b"*(1.0/du)", b"*du")
        data = data.replace(b"let( (curdsnunit)", b"let( (curdsnunit du old_visList)")
    elif name == "fTextTuneTools.il":
        # Use the original built-in simplified Chinese UI regardless of autosave.
        data = data.replace(b'LAN = axlGetVariable("autosave_dbcheck")', b'LAN = nil')
        data = data.replace(b'FORM TOOLWINDOW', b'FORM')
        data = data.replace(b"'(e innter)", b"'(e inner)")
        data = data.replace(b'PORT 36 45', b'PORT 36 50')
        data = data.replace(b'FSIZE 35 40', b'FSIZE 35 45')
        data = data.replace(b'FSIZE 32 13', b'FSIZE 32 16')
        # Normal dialog enables the title-bar X; route it through original cleanup.
        data = data.replace(b'("F_btnExit"', b'(("F_btnExit" "done" "cancel")')
        data = re.sub(rb'(procedure\(fnTTExit\(frmTT\)\s*let\(\(\))',
                      rb'\1\n frmTT->xkClosing = t', data)
        data = data.replace(b'case(frmTT->curField', b'case(if(frmTT->xkClosing then "" else frmTT->curField)')
        data = data.replace(b'when(frmTT->doneState == 3',
                            b'when(frmTT->doneState == 3 && not(frmTT->xkClosing) && fboundp(\'fnTTExit)')
        # Native X closes the form before dispatch. Keep the existing restore
        # option in user data so cleanup never reads an already closed control.
        data = data.replace(b'when(axlFormGetField(frmTT "F_chkRestoreView")',
                            b'when(frmTT->xkRestoreView')
        data = data.replace(b'\t\tfnTTSetFormField(frmTT)\r\n',
                            b'\t\tfnTTSetFormField(frmTT)\r\n frmTT->xkRestoreView = axlFormGetField(frmTT "F_chkRestoreView")\r\n')
        data = data.replace(b'case(if(frmTT->xkClosing then "" else frmTT->curField)',
                            b'case(if(frmTT->xkClosing then "" else frmTT->curField)\n ("F_chkRestoreView" frmTT->xkRestoreView = frmTT->curValue)')
        # Give the colour row enough room before the next group begins.
        start = data.index(b'fprintf(pTTForm "FIELD F_clrTop')
        end = data.index(b'fprintf(pTTForm "FSIZE 32 6', start)
        region = data[start:end].replace(b'xY = xY + 2', b'xY = xY + 5')
        region = region.replace(b'TLOC %d %d\\n" xX xY)', b'TLOC %d %d\\n" xX (xY + 1))')
        data = data[:start] + region + data[end:]
    elif name == "check_no_refdes.il":
        # A component without silk needs its body visible to show highlighting.
        marker = b'axlVisibleLayer( "PIN/TOP" t )'
        data = data.replace(marker, marker + b'\n' + b'\n'.join(
            f'axlVisibleLayer("PACKAGE GEOMETRY/{layer}_{side}" t)'.encode()
            for layer in ('ASSEMBLY', 'PLACE_BOUND') for side in ('TOP', 'BOTTOM')))
        data += b'\n'
        # Closing the log only writes it; explicitly show Allegro's report viewer.
        # Keep the report on disk when the viewer is closed.
        title = ''.join(f'\\{byte:03o}' for byte in 'D7 缺失丝印位号检查报告'.encode('gbk'))
        data = data.replace(b'axlDMClose(logfile)',
            b'axlDMClose(logfile)\n axlVisibleUpdate(t)\n axlZoomFit(nil \'visible)\n axlUIWRedraw(nil)\n axlUIWExpose(axlUIViewFileCreate("no_refdes.log" "'
            + title.encode('ascii') + b'" nil))')
    elif name == "gxl_wdzcheck_text_overlap.il":
        labels = {
            "Checking Text Overlap Form": "D8 丝印重叠检查（增强版）",
            "Select Checking Layer:": "选择检查层：", "Clearance:": "检查间距：",
            "Text to Pin": "文字与焊盘", "Text to Testpoint": "文字与测试点",
            "Text to Text": "文字与文字", "Refdes to component": "位号与封装",
            "Bar Code Overlap": "条码重叠", "View error:": "检查结果：",
            "Tatol: %d": "共 %d 项", "Done": "关闭", "Check": "检查",
            "unSelect": "取消高亮",
        }
        for old, new in labels.items():
            # Change displayed labels only, never identifiers/algorithms.
            data = data.replace((r'\"'+old+r'\"').encode(), (r'\"'+new+r'\"').encode('gbk'))
        data = data.replace(b'Tatol: %d', '共 %d 项'.encode('gbk'))
        data = data.replace(b'PORT 26 10', b'PORT 50 31')
        data = data.replace(b'FLOC 12 6', b'FLOC 14 6')
        data = data.replace('MENUBUTTON \\"关闭\\" 5 3'.encode('gbk'), 'MENUBUTTON \\"关闭\\" 8 3'.encode('gbk'))
        data = data.replace(b'FLOC 8 26', b'FLOC 13 26').replace(b'FLOC 15 26', b'FLOC 24 26')
        data = data.replace('MENUBUTTON \\"检查\\" 5 3'.encode('gbk'), 'MENUBUTTON \\"检查\\" 8 3'.encode('gbk'))
        data = data.replace('MENUBUTTON \\"取消高亮\\" 6 3'.encode('gbk'), 'MENUBUTTON \\"取消高亮\\" 10 3'.encode('gbk'))
        # Literal tab before newlines disables legacy automatic field spreading.
        builder_end = data.index(b'(defun pform_Action')
        data = data[:builder_end].replace(b'\\n', b'\\t\\n') + data[builder_end:]
        data = data.replace(b'("done"', b'(("done" "cancel")')
        data = isolate_overlap_symbols(data)
    if name == "jkcheck_refdes_cross.il":
        data = data.replace(b'shell("rm ./setColor.scr")', b'when(isFile("./setColor.scr") deleteFile("./setColor.scr"))')
    (root / "skill" / name).write_bytes(data)

source = (root / "src" / "xiaokaiViewTools.il").read_text(encoding="utf-8") + "\n" + (root / "src" / "xiaokaiAllegroMenu.il").read_text(encoding="utf-8")
encoded = "".join(
    char if ord(char) < 128 else "".join(f"\\{byte:03o}" for byte in char.encode("gbk"))
    for char in source
)
(root / "skill" / "xiaokaiAllegroMenu.il").write_bytes(encoded.encode("ascii"))

text_source = (root / "src/xiaokaiTextTools.il").read_text(encoding="utf-8")
(root / "skill/xiaokaiTextTools.il").write_bytes("".join(
    char if ord(char) < 128 else "".join(f"\\{byte:03o}" for byte in char.encode("gbk"))
    for char in text_source).encode("ascii"))

# Keep upstream snapshots intact; omit the old name in shipped SKILL UI/files.
for skill_file in (root / "skill").glob("*.il"):
    if skill_file.name == "x_silk_in_out.il":
        continue  # Encrypted original must remain byte-identical.
    content = skill_file.read_bytes()
    content = re.sub(rb'^[^\r\n]*kevin[ \t]*wong[^\r\n]*(?:\r?\n|$)', b'', content, flags=re.I | re.M)
    content = re.sub(rb'\s*-\s*kevin\b', b'', content, flags=re.I)
    assert not re.search(rb'kevin\s*wong', content, re.I), skill_file.name
    skill_file.write_bytes(content)
