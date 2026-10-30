; Ignore initialization and title-bar close events before the legacy grid parser.
unless(boundp('xkOriginalGridAct) xkOriginalGridAct = getd('Grid_act))
procedure(Grid_act(form)
  let((field)
    field = form->curField
    cond(
      (member(form->doneState '(1 2 3)) || member(field '("done" "cancel"))
        axlFormClose(form))
      (stringp(field) && member(field
          '("1_mil" "5_mil" "10_mil" "20_mil" "50_mil" "100_mil"
            "0.05_mm" "0.1_mm" "0.25_mm" "0.5_mm" "1_mm" "2.5_mm"))
        unless(errset(apply(xkOriginalGridAct list(form)) t)
          axlUIWPrint(form "格点设置未完成，请重新选择格点。")))
    )
    t
  )
)

; Live component filtering uses the companion UI because Allegro STRFILLIN
; dispatches edits only when focus leaves the field. Database access stays here.
procedure(xkFindComponent()
  let((names port)
    when(axlDBGetDesign()
      foreach(component axlDBGetDesign()->components
        when(component->symbol names = cons(component->name names)))
      xkComponentNames = sort(names 'alphalessp)
      unless(boundp('xkComponentDataFile) xkComponentDataFile = axlTempFile())
      port = outfile(xkComponentDataFile)
      when(port
        foreach(name xkComponentNames fprintf(port "%s\n" name))
        close(port)
        ipcWriteProcess(xkToolboxHotkeyProcess strcat("COMPONENTS " xkComponentDataFile "\n"))
      )
    )
  )
)

procedure(xkLocateComponent(indexValue)
  let((name component box margin side)
    name = nth(indexValue xkComponentNames)
    component = car(setof(c axlDBGetDesign()->components c->name == name))
    when(component && component->symbol
      side = if(component->symbol->isMirrored then "BOTTOM" else "TOP")
      axlVisibleDesign(nil)
      foreach(layer list(strcat("PACKAGE GEOMETRY/SILKSCREEN_" side)
          strcat("REF DES/SILKSCREEN_" side) strcat("PIN/" side)
          strcat("VIA CLASS/" side) strcat("ETCH/" side))
        axlVisibleLayer(layer t))
      axlVisibleUpdate(t)
      when(boundp('xkLocatedComponent) && xkLocatedComponent
        foreach(previous axlDBGetDesign()->components
          when(previous->name == xkLocatedComponent && previous->symbol
            axlDehighlightObject(previous->symbol))))
      axlHighlightObject(component->symbol)
      xkLocatedComponent = name
      box = component->symbol->bBox
      margin = axlMKSConvert(100 "MILS")
      axlWindowBoxSet(list((caar(box)-margin):(cadar(box)-margin)
        (caadr(box)+margin):(cadadr(box)+margin)))
    )
  )
)
axlCmdRegister("find component" 'xkFindComponent)
axlCmdRegister("xk_find_component" 'xkFindComponent)

procedure(xkFindDrc()
  let((port)
    when(axlDBGetDesign()
      xkDrcRows = foreach(mapcar drc axlDBGetDesign()->drcs
        list(drc->name drc->layer drc->actual drc->expected drc->xy))
      unless(boundp('xkDrcDataFile) xkDrcDataFile = axlTempFile())
      port = outfile(xkDrcDataFile)
      when(port
        foreach(row xkDrcRows
          fprintf(port "%s\t%s\t%s\t%s\t%f\t%f\t\n"
            car(row) or(cadr(row) "") or(caddr(row) "") or(cadddr(row) "")
            car(nth(4 row)) cadr(nth(4 row))))
        close(port)
        ipcWriteProcess(xkToolboxHotkeyProcess strcat("DRCS " xkDrcDataFile "\n"))
      )
    )
  )
)
procedure(xkLocateDrc(indexValue)
  let((row xy layerName margin)
    row = nth(indexValue xkDrcRows)
    when(row
      xy = nth(4 row)
      axlVisibleLayer(cadr(row) t)
      layerName = car(last(parseString(cadr(row) "/")))
      when(member(layerName axlGetParam("paramLayerGroup:ETCH")->groupMembers)
        foreach(group '("ETCH/" "PIN/" "VIA CLASS/") axlVisibleLayer(strcat(group layerName) t)))
      axlVisibleUpdate(t)
      margin = axlMKSConvert(500 "MILS")
      axlWindowBoxSet(list((car(xy)-margin):(cadr(xy)-margin) (car(xy)+margin):(cadr(xy)+margin)))
    )
  )
)
axlCmdRegister("find drc" 'xkFindDrc ?cmdType "general")
axlCmdRegister("xk_find_drc" 'xkFindDrc ?cmdType "general")

; Visibility profiles are data, never executable SKILL files.
procedure(xkViewProfilePath()
  strcat(xkAllegroInstallRoot "/xiaokai_view_profiles.dat")
)
procedure(xkViewReadProfiles()
  let((port data)
    xkViewProfiles = nil
    when(isFile(xkViewProfilePath())
      port = infile(xkViewProfilePath())
      data = errset(lineread(port) t)
      close(port)
      when(data && listp(caar(data)) xkViewProfiles = caar(data))
    )
  )
)

procedure(xkViewFormText(value)
  let((result character)
    result = ""
    for(i 1 strlen(value)
      character = substring(value i 1)
      result = strcat(result cond(
        (character == "\"" "\\\"")
        (character == "\\" "\\\\")
        (member(character '("\r" "\n" "\t")) " ")
        (t character))))
    result
  )
)
procedure(xkViewProfileFields(port)
  xkViewReadProfiles()
  fprintf(port "TEXT \"自定义显示配置\"\nTLOC 58 1\nENDTEXT\n")
  let((row profile)
    for(i 0 9
      row = 4 + i * 2
      profile = nth(i xkViewProfiles)
      fprintf(port "FIELD name_%d\nFLOC 58 %d\nSTRFILLIN 20 80\nVALUE \"%s\"\nENDFIELD\n"
        i row xkViewFormText(if(profile then car(profile) else sprintf(nil "P%d" i+1))))
      fprintf(port "FIELD save_%d\nFLOC 80 %d\nMENUBUTTON \"保存\" 8 2\nENDFIELD\n" i row)
      fprintf(port "FIELD load_%d\nFLOC 89 %d\nMENUBUTTON \"读取\" 8 2\nENDFIELD\n" i row)
    )
  )
)

; Keep the original layer lists and actions, with one aligned row grid.
procedure(xkViewPresetLabel(name)
  let((translated)
    translated = assoc(name '(("TOP_SILK" "顶层丝印") ("BOTTOM_SILK" "底层丝印")
      ("TOP_PLACE" "顶层布局") ("BOTTOM_PLACE" "底层布局")
      ("ALL_PLACE" "双面布局") ("ALL_VIEW" "综合显示")
      ("TB_LAYOUT" "顶底层走线") ("TOP_LAYOUT" "顶层走线") ("BOTTOM_LAYOUT" "底层走线")))
    if(translated then cadr(translated) else
      strcat(substring(name 1 strlen(name)-7) " 走线"))
  )
)
procedure(Quick_Displayform()
  let((path port row labels label)
    disetchlayerlist = crlistneed()
    onofflistneed()
    path = strcat(axlTempFile() ".form")
    port = outfile(path "w")
    when(port
      fprintf(port "FILE_TYPE=FORM_DEFN VERSION=2\nFORM\nFIXED\nPORT 102 %d\nHEADER \"A4 快速切换层显示\"\nTILE\n"
        4+2*max(10 length(disetchlayerlist)))
      fprintf(port "TEXT \"显示预设\"\nTLOC 3 1\nENDTEXT\nTEXT \"显示开关\"\nTLOC 28 1\nENDTEXT\n")
      row = 4
      foreach(preset disetchlayerlist
        fprintf(port "FIELD %L\nFLOC 3 %d\nFGROUP \"displayl\"\nCHECKLIST \"%s\" \"displayl\"\nENDFIELD\n"
          car(preset) row xkViewPresetLabel(car(preset)))
        row = row+2)
      labels = '(("SilkT" "顶层丝印") ("SilkB" "底层丝印")
        ("PlacT" "顶层装配轮廓") ("PlacB" "底层装配轮廓")
        ("Allant" "全部反相铜层") ("AllDrc" "全部 DRC 标记") ("AllEtch" "全部走线"))
      row = 4
      foreach(group onoffalllist
        label = assoc(car(group) labels)
        fprintf(port "FIELD %L\nFLOC 28 %d\nMENUBUTTON \"%s\" 24 2\nENDFIELD\n"
          car(group) row if(label then cadr(label) else strcat(car(group) " 走线")))
        row = row+2)
      xkViewProfileFields(port)
      ; A final text row keeps Allegro from treating the last layer as a footer button row.
      fprintf(port "TEXT \"显示开关可叠加使用，自定义配置保存全部层的显示状态。\"\nTLOC 3 %d\nENDTEXT\n"
        4+2*max(10 length(disetchlayerlist)))
      fprintf(port "ENDTILE\nENDFORM\n")
      close(port)
      displayform = axlFormCreate((gensym) path '(c inner) 'Display_current t)
      when(displayform
        axlFormDisplay(displayform)
        axlUIWPrint(displayform "选择预设切换显示；开关按钮切换对应层；右侧保存、读取当前显示配置。"))
      deleteFile(path)
    )
  )
)

procedure(xkViewWriteProfiles()
  let((port)
    port = outfile(xkViewProfilePath() "w")
    when(port fprintf(port "%L\n" xkViewProfiles) close(port))
  )
)

procedure(xkViewProfileAction(form)
  let((field name profile indexValue newProfile profiles)
    field = form->curField
    when(stringp(field) cond(
      (or(rexMatchp("^save_" field) rexMatchp("^load_" field) rexMatchp("^name_" field))
        indexValue = atoi(cadr(parseString(field "_")))
        profile = nth(indexValue xkViewProfiles)
        name = axlFormGetField(form sprintf(nil "name_%d" indexValue))
        if(rexMatchp("^load_" field) then
          if(profile && cadr(profile) then
            axlVisibleSet(cadr(profile))
            axlVisibleUpdate(t)
            axlUIWPrint(form strcat("已读取：" car(profile)))
          else axlUIWPrint(form "此配置尚未保存。"))
        else
          if(name == "" then axlUIWPrint(form "请输入配置名称。") else
            newProfile = list(name if(rexMatchp("^save_" field) then axlVisibleGet() else cadr(profile)))
            for(i 0 max(9 length(xkViewProfiles)-1)
              profiles = append1(profiles if(i == indexValue then newProfile else
                or(nth(i xkViewProfiles) list(sprintf(nil "P%d" i+1) nil)))))
            xkViewProfiles = profiles
            if(xkViewWriteProfiles() then
              axlUIWPrint(form strcat(if(rexMatchp("^save_" field) then "已保存：" else "已重命名：") name))
            else axlUIWPrint(form "配置文件保存失败。"))
          )
        )
        t
      )
    ))
  )
)

unless(boundp('xkOriginalDisplayCurrent) xkOriginalDisplayCurrent = getd('Display_current))
procedure(Display_current(form)
  unless(xkViewProfileAction(form) apply(xkOriginalDisplayCurrent list(form)))
)

; Validate paths first, then serialize balanced quotes for the file API.
; Unlike axlSetVariable, axlSetVariableFile requires a scalar value.
procedure(xkPathSlashes(value)
  let((result character)
    result = ""
    for(i 1 strlen(value)
      character = substring(value i 1)
      result = strcat(result if(character == "\\" then "/" else character)))
    result
  )
)
procedure(xkPathQuote(value)
  strcat("\"" xkPathSlashes(value) "\"")
)
procedure(xkParseLibraryPaths(value)
  let((paths token quoted character)
    token = ""
    value = xkPathSlashes(or(value ""))
    for(i 1 strlen(value)
      character = substring(value i 1)
      cond(
        (character == "\"" quoted = not(quoted))
        (not(quoted) && member(character '(" " "\t" "\r" "\n"))
          when(token != "" paths = append1(paths token) token = ""))
        (t token = strcat(token character))
      )
    )
    when(token != "" paths = append1(paths token))
    list(not(quoted) paths)
  )
)
procedure(xkLibraryAction(form)
  let((field variable directory value failed parsed settings result invalid)
    field = form->curField
    when(stringp(field) cond(
      (rexMatchp("^browse_" field)
        variable = cadr(parseString(field "_"))
        directory = axlDMDirectoryBrowse("." nil ?title "选择库目录")
        when(directory
          value = axlFormGetField(form variable)
          axlFormSetField(form variable strcat(value " " xkPathQuote(directory)))
        )
      )
      (field == "apply"
        foreach(variable '("psmpath" "padpath" "devpath")
          parsed = xkParseLibraryPaths(axlFormGetField(form variable))
          if(car(parsed) then settings = append1(settings list(variable cadr(parsed)))
          else invalid = cons(upperCase(variable) invalid))
        )
        if(invalid then
          axlUIWPrint(form sprintf(nil "%L 的双引号未闭合，请补齐后保存。" invalid))
        else
          foreach(setting settings
            value = buildString(foreach(mapcar directory cadr(setting) xkPathQuote(directory)) " ")
            result = errset(axlSetVariableFile(car(setting) value) t)
            unless(result && car(result) failed = cons(upperCase(car(setting)) failed)))
          if(failed then
            axlUIWPrint(form sprintf(nil "保存失败：%L" failed))
          else axlUIWPrint(form "库路径已保存并立即生效。"))
        )
      )
      (member(field '("done" "cancel")) axlFormClose(form))
    ))
  )
  t
)

procedure(xkLibraryPaths()
  let((definition row form pathText)
    definition = strcat("FILE_TYPE=FORM_DEFN VERSION=2\t\nFORM\t\nFIXED\t\nPORT 112 28\t\n"
      "HEADER \"A7 修改库路径\"\t\nTILE\t\n")
    row = 1
    foreach(variable '("psmpath" "padpath" "devpath")
      definition = strcat(definition sprintf(nil
        "TEXT %L\t\nTLOC 2 %d\t\nENDTEXT\t\nFIELD %s\t\nFLOC 2 %d\t\nSTRFILLIN 90 4096\t\nENDFIELD\t\nFIELD browse_%s\t\nFLOC 94 %d\t\nMENUBUTTON \"添加目录\" 14 3\t\nENDFIELD\t\n"
        upperCase(variable) row variable row+3 variable row+3))
      row = row + 8
    )
    definition = strcat(definition
      "TEXT \"可填写多个目录；含空格的目录用双引号包围。\"\t\nTLOC 2 26\t\nENDTEXT\t\n"
      "FIELD apply\t\nFLOC 90 30\t\nMENUBUTTON \"保存设置\" 18 3\t\nENDFIELD\t\nENDTILE\t\nENDFORM\t\n")
    form = axlFormCreate('xkLibraryForm list("xk_library_paths" definition) '(c inner) 'xkLibraryAction t)
    when(form
      foreach(variable '("psmpath" "padpath" "devpath")
        pathText = ""
        foreach(directory axlGetVariableList(variable)
          pathText = strcat(pathText xkPathQuote(directory) " "))
        axlFormSetField(form variable pathText)
      )
      axlFormDisplay(form)
    )
  )
)
axlCmdRegister("xk_library_paths" 'xkLibraryPaths)
