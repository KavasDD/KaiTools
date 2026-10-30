"""Build isolated C tools from immutable upstream snapshots and explicit adapters."""
from pathlib import Path
from hashlib import sha256
import json
import re

root = Path(__file__).resolve().parent
protected = r'"(?:\\.|[^"\\])*"|;[^\n]*|/\*[\s\S]*?\*/'

def strip_comments(s):
    return re.sub(protected, lambda m: m[0] if m[0].startswith('"') else ' ', s)

def replace_function(s, name, replacement):
    m = re.search(r'\(defun\s+' + re.escape(name) + r'\s*\(|(?:defun|procedure)\(\s*' + re.escape(name) + r'\s*\(', s)
    assert m, name
    start = m.start()
    # defun(foo ...) without a leading ( is also accepted by SKILL.
    scan = start if s[start] == '(' else s.index('(', start)
    depth = 0
    for t in re.finditer(r'"(?:\\.|[^"\\])*"|[()]', s[scan:]):
        if t[0] == '(':
            depth += 1
        elif t[0] == ')':
            depth -= 1
            if depth == 0:
                return s[:start] + replacement + s[scan+t.end():]
    raise AssertionError(name)

def isolate(s, prefix):
    mask = re.sub(protected, lambda m: ' '*len(m[0]), s)
    names = set(re.findall(r'(?<![\w>])([A-Za-z_]\w*)\s*=(?!=)', mask))
    names.update(re.findall(r'(?:defun|procedure)\s*\(?\s*([A-Za-z_]\w*)', mask))
    names.update(re.findall(r'\b(?:foreach|for)\s*\(\s*(\w+)', mask))
    names.update(re.findall(r'\b_?lgs_\w+', mask))
    # Include parameters even if the source never assigns them.
    for match in re.finditer(r'(?:defun|procedure)\s*\(?\s*\w+\s*\(([^()]*)\)', mask):
        names.update(re.findall(r'\b\w+\b', match[1]))
    names.difference_update(('t', 'nil'))
    tokens = re.compile(protected + r'|(?<!->)(?<!~>)(?<![\w])\b[A-Za-z_]\w*\b')
    return tokens.sub(lambda m: prefix+m[0] if m[0] in names else m[0], s)

def encode(s):
    return ''.join(c if ord(c)<128 else ''.join('\\%03o'%b for b in c.encode('gbk')) for c in s).encode('ascii')

def form(title, port, body):
    return 'FILE_TYPE=FORM_DEFN VERSION=2\t\nFORM\t\nFIXED\t\nPORT '+port+'\t\nHEADER "'+title+'"\t\nTILE\t\n'+body+'ENDTILE\t\nENDFORM\t\n'

def field(name,x,y,kind):
    return f'FIELD {name}\t\nFLOC {x} {y}\t\n{kind}\t\nENDFIELD\t\n'

def text(label,x,y):
    return f'TEXT "{label}"\t\nTLOC {x} {y}\t\nENDTEXT\t\n'

def skillstr(s):
    return '"'+s.replace('\\','\\\\').replace('"','\\"').replace('\t','\\t').replace('\n','\\n')+'"'

def create_function(name,var,callback,title,port,body,modal='t',extra=''):
    definition=skillstr(form(title,port,body))
    return f'procedure({name}()\n {var}=axlFormCreate((gensym) list("{name}" {definition}) \'(e inner) \'{callback} {modal})\n when({var} axlFormDisplay({var}) {extra})\n)'

hashes = json.loads((root/'originals/c-tools-hashes.json').read_text(encoding='utf-8-sig'))
for name, expected in hashes.items():
    data=(root/'originals'/name).read_bytes()
    assert sha256(data).hexdigest().lower()==expected.lower(), name
    if name in ('find_stubs.il', 'lgs_loop90_check.il', 'checkWidth.il', 'StackVias.il'):
        (root/'skill'/name).unlink(missing_ok=True)
        continue  # Withdrawn from the selected collection; snapshots retained.
    if name in ('find_pin_no_past.il','find_pin_no_solder.il'):
        (root/'skill'/name).write_bytes(data)
        continue
    if name in ('checkWidth.il','StackVias.il'):
        continue
    s=strip_comments(data.decode('gbk',errors='replace').replace('\r',''))
    number={'find_stubs.il':1,'lgs_loop90_check.il':2,'lgs_hilight_no_fanout.il':5,'lgs_check_solder_to_line_V1_0.il':7,'quick_chSmd2ThrP.il':8}[name]
    if number==1:
        body=text('悬空走线候选；选中后定位',2,1)+field('Stub_List_Field',2,4,'LIST "" 70 12')
        body+=text('',2,24).replace('TEXT ""','TEXT').replace('ENDTEXT','INFO Msg_Field 70\t\nENDTEXT')
        body+=field('Remove_Field',2,28,'MENUBUTTON "移除标记" 18 3')+field('Delete_Field',24,28,'MENUBUTTON "删除走线" 18 3')
        definition=skillstr(form('C1：悬空走线检查','74 33',body))
        s=replace_function(s,'CreateForm',f'procedure(CreateForm() form_file="./xkC1_find_stubs.form" form=outfile(form_file "w") fprintf(form "%s" {definition}) close(form))')
        s=s.replace('("Exit_Field"','(("Exit_Field" "done" "cancel")')
        s=s.replace('axlFormClose(Stub_Find_Form)','unless(Stub_Find_Form->doneState == 3 axlFormClose(Stub_Find_Form))')
        for old,new in [('No stubs were found','未发现悬空走线'),('Select stub from list','选择列表中的走线以定位'),('No more stubs','列表为空')]: s=s.replace(old,new)
    elif number==2:
        s=s.replace('lgs_zoom = 0','lgs_zoom = 0\n lgs_zoom_i=270')
        s=replace_function(s,'_lgs_get_match_netname', '''procedure(_lgs_get_match_netname(lgs_filter)
 let((result) foreach(net axlDBGetDesign()->nets
   when(net->name && _lgs_match_name(net->name if(lgs_filter=="" || lgs_filter=="*" then "*" else strcat("*" lgs_filter "*"))) result=cons(net->name result)))
 sort(result nil)))''')
        s+='''
procedure(_lgs_match_name(name pattern)
 cond((pattern=="" name=="")
  (substring(pattern 1 1)=="*"
   or(_lgs_match_name(name if(strlen(pattern)>1 then substring(pattern 2) else ""))
      name!="" && _lgs_match_name(if(strlen(name)>1 then substring(name 2) else "") pattern)))
  (name!="" && (substring(pattern 1 1)=="?" || substring(pattern 1 1)==substring(name 1 1))
   _lgs_match_name(if(strlen(name)>1 then substring(name 2) else "") if(strlen(pattern)>1 then substring(pattern 2) else "")))
  (t nil)))
'''
        s=replace_function(s,'_lgs_ac_form_callback','''procedure(_lgs_ac_form_callback(lgs_ac_form)
 let((field value selected box point margin)
  field=lgs_ac_form->curField value=lgs_ac_form->curValue
  case(field
   ("lgs_net_err"
    lgs_list_mode=if(value=="net" then "net" else "err")
    axlFormListDeleteAll(lgs_ac_form "Err_List")
    selected=if(lgs_list_mode=="net" then lgs_netlist else lgs_errlist)
    when(selected axlFormSetField(lgs_ac_form "Err_List" selected)))
   ("Ref_Des_Filter"
    lgs_filter=value lgs_netlist=_lgs_get_match_netname(lgs_filter)
    lgs_list_mode="net"
    axlFormSetField(lgs_ac_form "lgs_net_err" "net")
    axlFormListDeleteAll(lgs_ac_form "Err_List")
    when(lgs_netlist axlFormSetField(lgs_ac_form "Err_List" lgs_netlist))
    axlUIWPrint(lgs_ac_form "找到 %d 个网络" length(lgs_netlist)))
   ("lgs_loop" when(value lgs_command=0))
   ("lgs_90degree" when(value lgs_command=1))
   ("lgs_length" lgs_degree_length=value)
   ("lgs_check" lgs_number=0 _lgs_ac_check())
   ("shadow_bright" lgs_zoom=value
    axlFormSetField(lgs_ac_form "shadow_factor" sprintf(nil "%d%%" lgs_zoom)))
   ("Err_List"
    when(stringp(value)
     margin=axlMKSConvert(270-2.5*lgs_zoom "mils")
     if(lgs_list_mode=="err" then
      when(lgs_ac_form->curValueInt>=0 && lgs_ac_form->curValueInt<length(lgs_errlistxy)
       point=nth(lgs_ac_form->curValueInt lgs_errlistxy)
       box=list(point point))
     else
      selected=car(setof(net axlDBGetDesign()->nets net->name==value))
      when(selected box=selected->bBox))
     when(box axlWindowBoxSet(list((caar(box)-margin):(cadar(box)-margin) (caadr(box)+margin):(cadadr(box)+margin))))))
   (("lgsdone" "done" "cancel") unless(lgs_ac_form->doneState==3 axlFormClose(lgs_ac_form))))
  t))''')
        s=s.replace('lgs_temp_net = car(axlGetSelSet(axlSingleSelectName("NET" netname)))','lgs_temp_net = car(setof(net axlDBGetDesign()->nets net->name == netname))')
        body='POPUP <key_Names>"网络" "net","结果" "error".\t\n'
        body+=field('lgs_net_err',2,1,'ENUMSET 12\t\nPOP "key_Names"')+text('筛选',17,1)+field('Ref_Des_Filter',25,1,'STRFILLIN 43 80')
        body+=field('Err_List',2,5,'LIST "" 66 12')
        body+=field('lgs_loop',2,24,'CHECKLIST "环路" "loop_degree"')+field('lgs_90degree',22,24,'CHECKLIST "直角/锐角" "loop_degree"')
        body+=text('最短段长（当前单位）',2,28)+field('lgs_length',42,28,'REALFILLIN 15 15\t\nREALMIN 0')
        body+=text('缩放',2,32)+field('shadow_bright',12,32,'TRACKBAR 42 4\t\nMIN 0\t\nMAX 100')
        body+='TEXT\t\nTLOC 58 32\t\nINFO shadow_factor 8\t\nENDTEXT\t\n'+field('lgs_check',2,38,'MENUBUTTON "开始检查" 22 3')
        s=replace_function(s,'_lgs_make_acform',create_function('_lgs_make_acform','lgs_ac_form','_lgs_ac_form_callback','C2：环路与直角/锐角检查','72 43',body))
        # The obsolete form-file cleanup is inapplicable to the in-memory form.
        s=s.replace('("lgsdone"','(("lgsdone" "done" "cancel")').replace('axlFormClose( lgs_ac_form)','unless(lgs_ac_form->doneState == 3 axlFormClose(lgs_ac_form))')
        s=s.replace('deleteFile("./lgs_auto_check_form.form")','t')
        s=s.replace('lgs_temp = round( 100*percent/all)','lgs_temp = if(all>0 then round(100*percent/all) else 100)')
        s=s.replace('(x = x22)','(x == x22)').replace('(x = x2)','(x == x2)')
        # Keep the original geometric algorithm and its path-count limit.
        s=s.replace('lgs_temp1 > lgs_temp2-1 || lgs_temp1 < lgs_temp2+1','lgs_temp1 > lgs_temp2-1 && lgs_temp1 < lgs_temp2+1')
        # Direct lookup also permits list navigation when the net is invisible.
        s=s.replace('car(axlGetSelSet(axlSingleSelectName("NET" lgs_ac_form->curValue)))->bBox','car(setof(net axlDBGetDesign()->nets net->name==lgs_ac_form->curValue))->bBox')
        s=s.replace('axlSetFindFilter(?enabled \'(noall nets) ?onButtons \'(noall nets))\n\t\t\taxlSingleSelectName("NET" lgs_ac_form->curValue)','t')
        s=s.replace('axlFormSetField( lgs_ac_form "Err_List" lgs_netlist)','when(lgs_netlist axlFormSetField(lgs_ac_form "Err_List" lgs_netlist))')
        s=s.replace('axlFormSetField( lgs_ac_form "Err_List" lgs_errlist)','when(lgs_errlist axlFormSetField(lgs_ac_form "Err_List" lgs_errlist))')
    elif number in (5,7):
        # Modeless callbacks run after the outer LET has returned. Initialize
        # the isolated persistent state explicitly before creating the form.
        if number==5:
            s=re.sub(r'let\(\s*\( lgs_smd_bBox[^)]*\)', 'let(()\n lgs_hilight_bBox=nil\n lgs_view_number=0', s, count=1)
        body=''
        if number==7:
            body+=text('间距（当前设计单位）',2,1)+field('lgs_distance_D',42,1,'REALFILLIN 12 12\t\nREALMIN 0')
            body+=text('斜向距离',2,5)+field('lgs_distance_O',42,5,'REALFILLIN 12 12\t\nREALMIN 0')
            body+=field('stol_checksamenet',2,9,'CHECKLIST "同时检查同网络"')
        y=13 if number==7 else 2
        body+=field('lgs_h_top',2,y,'MENUBUTTON "检查顶层" 24 3')+field('lgs_h_botm',30,y,'MENUBUTTON "检查底层" 24 3')
        body+=field('lgs_info',2,y+5,'STRFILLIN 54 80')
        for key,label,x in [('first','首项',2),('prev','上一项',16),('next','下一项',30),('last','末项',44)]:
            body+=field('lgs_'+key,x,y+10,f'MENUBUTTON "{label}" 12 3')
        if number==7:
            body+=text('缩放',2,y+15)+field('lgs_zoom',12,y+15,'TRACKBAR 32 4\t\nMIN 0\t\nMAX 100')
            body+='TEXT\t\nTLOC 46 28\t\nINFO shadow_factor 8\t\nENDTEXT\t\n'
            s=replace_function(s,'_lgs_check_solder_to_line_main_form',create_function('_lgs_check_solder_to_line_main_form','lgs_stol_main_form','_lgs_stol_main_back','D3：焊盘与走线间距检查','58 34',body))
            s=s.replace('axlUIWPrint( lgs_progress_form', 'axlUIWPrint( lgs_stol_main_form')
        else:
            s=replace_function(s,'_lgs_creat_hilight_smd_main_form',create_function('_lgs_creat_hilight_smd_main_form','lgs_hilight_smd_main_form','_lgs_hilight_smd_main_back','D2：未扇出 SMD 引脚检查','58 19',body))
        s=re.sub(r'(?m)^(\s*)\("done"',r'\1(("done" "cancel")',s)
        s=re.sub(r'axlFormClose\(\s*(lgs_(?:stol_main_form|hilight_smd_main_form))\s*\)',r'unless(\1->doneState == 3 axlFormClose(\1))',s)
    elif number==8:
        s=s.replace('INTFILLIN 8 8','REALFILLIN 8 12').replace('"clearance" 120','"clearance" axlMKSConvert(120 "mils")')
        s=s.replace('axlFormSetField(Smd2Tform "BTM" t)','axlFormSetField(Smd2Tform "BTM" t)\n total=0\n axlFormSetField(Smd2Tform "next_view" "0/0")')
        s=s.replace('("exit"','(("exit" "done" "cancel")').replace('axlFormClose(Smd2Tform)','unless(Smd2Tform->doneState == 3 axlFormClose(Smd2Tform))')
        s=s.replace('elemlist = sym->symbol->children','cursymbox=nil\n elemlist = sym->symbol->children').replace('\n\t\tcursymbox','\n\t\tor(cursymbox sym->symbol->bBox)')
        s=s.replace('if(cursympin1->isThrough','if(cursympin1 && cursympin1->isThrough').replace('if(cursympin1->isMirrored','if(cursympin1 && cursympin1->isMirrored')
        s=s.replace('defun(check_highl (item)', 'defun(check_highl (item)').replace('allsym = axlDBGetDesign()->components','total=0\n hlloclist=nil\n allsym = setof(component axlDBGetDesign()->components component->pins)')
        for a,b in [('Smd2ThrP check','D4：SMD 与通孔引脚间距检查'),('The layer to be checked: ','检查面'),('Input the min clearance: ','最小间距（当前设计单位）'),('Min: ','间距'),('Top','顶层'),('Bottom','底层'),('Check','检查'),('Exit','关闭')]:
            s=s.replace('\\"'+a+'\\"','\\"'+b+'\\"')
        s=s.replace('PORT 29 6','PORT 36 21')
        s=s.replace('(max(tp top bm bottom)+max(tp top bm bottom))','(max(tp top bm bottom)+min(tp top bm bottom))')
        s=s.replace('list(x-400:y-320 x+400:y+80)', 'list((x-axlMKSConvert(400 "mils")):(y-axlMKSConvert(320 "mils")) (x+axlMKSConvert(400 "mils")):(y+axlMKSConvert(320 "mils")))')
        s=s.replace('"ETCH//TOP"','"ETCH/TOP"').replace('"ETCH//BOTTOM"','"ETCH/BOTTOM"')
    messages={
      'Please check first!':'请先检查。', 'Hilight %d SMD Pin!':'发现 %d 个未扇出引脚',
      '%d of %d':'第 %d 项 / 共 %d 项', 'Checking Loop Error!':'正在检查环路…',
      'Checking Degree Error!':'正在检查直角/锐角…', '%d Loop Errors Be Find!':'发现 %d 个环路候选',
      '%d Degree Errors Be Find!':'发现 %d 个直角/锐角候选', '%d Nets Be Find!':'找到 %d 个网络',
      'Net List.':'网络列表', 'Error List.':'结果列表', 'Check Loop Error.':'环路检查',
      'Check Degree Error.':'直角/锐角检查', '%d%% complete!':'已完成 %d%%',
      '0%% complete!':'已完成 0%%', 'getting pins information.Please Wait...':'正在读取引脚…',
      'Finding SMD Pins without Fanout.Please Wait...':'正在检查未扇出引脚…',
      'Hilight SMD Pins without Fanout.Please Wait...':'正在高亮结果…',
      'Hilight SMD Pin without fanout V1.0':'未扇出引脚：检查进度',
      'Check Solder to Line V1.0':'焊盘与走线：检查进度',
      'Auto Check Progress V1.0':'环路与角度：检查进度',
      'Please choose the layer first!':'请先选择检查面。',
      'There is no need to check current layer':'当前面没有待检查对象。',
      'There is no erro at this layer!':'当前面没有检查结果。',
      'Kevin Wong':'D4：按当前设计单位检查',
    }
    for old,new in messages.items():
        s=s.replace('"'+old+'"','"'+new+'"').replace('\\"'+old+'\\"','\\"'+new+'\\"')
    # Isolate code symbols and temporary filenames, including shared progress forms.
    for filename in set(re.findall(r'"([^"\n]*\.form)"',s)):
        s=s.replace('"'+filename+'"','"'+('./' if filename.startswith('./') else '')+f'xkC{number}_'+filename.removeprefix('./')+'"')
    s=isolate(s,f'xkC{number}_')
    s=re.sub(r'\\n([ \t]*)"',r'\\t\\n\1"',s) # Allegro form rows use tab terminators.
    (root/'skill'/name).write_bytes(encode(s))

print('C checks: upstream hashes verified; isolated installation copies generated.')
