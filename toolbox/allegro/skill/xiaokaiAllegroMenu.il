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
          axlUIWPrint(form "\270\361\265\343\311\350\326\303\316\264\315\352\263\311\243\254\307\353\326\330\320\302\321\241\324\361\270\361\265\343\241\243")))
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
  fprintf(port "TEXT \"\327\324\266\250\322\345\317\324\312\276\305\344\326\303\"\nTLOC 58 1\nENDTEXT\n")
  let((row profile)
    for(i 0 9
      row = 4 + i * 2
      profile = nth(i xkViewProfiles)
      fprintf(port "FIELD name_%d\nFLOC 58 %d\nSTRFILLIN 20 80\nVALUE \"%s\"\nENDFIELD\n"
        i row xkViewFormText(if(profile then car(profile) else sprintf(nil "P%d" i+1))))
      fprintf(port "FIELD save_%d\nFLOC 80 %d\nMENUBUTTON \"\261\243\264\346\" 8 2\nENDFIELD\n" i row)
      fprintf(port "FIELD load_%d\nFLOC 89 %d\nMENUBUTTON \"\266\301\310\241\" 8 2\nENDFIELD\n" i row)
    )
  )
)

; Keep the original layer lists and actions, with one aligned row grid.
procedure(xkViewPresetLabel(name)
  let((translated)
    translated = assoc(name '(("TOP_SILK" "\266\245\262\343\313\277\323\241") ("BOTTOM_SILK" "\265\327\262\343\313\277\323\241")
      ("TOP_PLACE" "\266\245\262\343\262\274\276\326") ("BOTTOM_PLACE" "\265\327\262\343\262\274\276\326")
      ("ALL_PLACE" "\313\253\303\346\262\274\276\326") ("ALL_VIEW" "\327\333\272\317\317\324\312\276")
      ("TB_LAYOUT" "\266\245\265\327\262\343\327\337\317\337") ("TOP_LAYOUT" "\266\245\262\343\327\337\317\337") ("BOTTOM_LAYOUT" "\265\327\262\343\327\337\317\337")))
    if(translated then cadr(translated) else
      strcat(substring(name 1 strlen(name)-7) " \327\337\317\337"))
  )
)
procedure(Quick_Displayform()
  let((path port row labels label)
    disetchlayerlist = crlistneed()
    onofflistneed()
    path = strcat(axlTempFile() ".form")
    port = outfile(path "w")
    when(port
      fprintf(port "FILE_TYPE=FORM_DEFN VERSION=2\nFORM\nFIXED\nPORT 102 %d\nHEADER \"A4 \277\354\313\331\307\320\273\273\262\343\317\324\312\276\"\nTILE\n"
        4+2*max(10 length(disetchlayerlist)))
      fprintf(port "TEXT \"\317\324\312\276\324\244\311\350\"\nTLOC 3 1\nENDTEXT\nTEXT \"\317\324\312\276\277\252\271\330\"\nTLOC 28 1\nENDTEXT\n")
      row = 4
      foreach(preset disetchlayerlist
        fprintf(port "FIELD %L\nFLOC 3 %d\nFGROUP \"displayl\"\nCHECKLIST \"%s\" \"displayl\"\nENDFIELD\n"
          car(preset) row xkViewPresetLabel(car(preset)))
        row = row+2)
      labels = '(("SilkT" "\266\245\262\343\313\277\323\241") ("SilkB" "\265\327\262\343\313\277\323\241")
        ("PlacT" "\266\245\262\343\327\260\305\344\302\326\300\252") ("PlacB" "\265\327\262\343\327\260\305\344\302\326\300\252")
        ("Allant" "\310\253\262\277\267\264\317\340\315\255\262\343") ("AllDrc" "\310\253\262\277 DRC \261\352\274\307") ("AllEtch" "\310\253\262\277\327\337\317\337"))
      row = 4
      foreach(group onoffalllist
        label = assoc(car(group) labels)
        fprintf(port "FIELD %L\nFLOC 28 %d\nMENUBUTTON \"%s\" 24 2\nENDFIELD\n"
          car(group) row if(label then cadr(label) else strcat(car(group) " \327\337\317\337")))
        row = row+2)
      xkViewProfileFields(port)
      ; A final text row keeps Allegro from treating the last layer as a footer button row.
      fprintf(port "TEXT \"\317\324\312\276\277\252\271\330\277\311\265\376\274\323\312\271\323\303\243\254\327\324\266\250\322\345\305\344\326\303\261\243\264\346\310\253\262\277\262\343\265\304\317\324\312\276\327\264\314\254\241\243\"\nTLOC 3 %d\nENDTEXT\n"
        4+2*max(10 length(disetchlayerlist)))
      fprintf(port "ENDTILE\nENDFORM\n")
      close(port)
      displayform = axlFormCreate((gensym) path '(c inner) 'Display_current t)
      when(displayform
        axlFormDisplay(displayform)
        axlUIWPrint(displayform "\321\241\324\361\324\244\311\350\307\320\273\273\317\324\312\276\243\273\277\252\271\330\260\264\305\245\307\320\273\273\266\324\323\246\262\343\243\273\323\322\262\340\261\243\264\346\241\242\266\301\310\241\265\261\307\260\317\324\312\276\305\344\326\303\241\243"))
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
            axlUIWPrint(form strcat("\322\321\266\301\310\241\243\272" car(profile)))
          else axlUIWPrint(form "\264\313\305\344\326\303\311\320\316\264\261\243\264\346\241\243"))
        else
          if(name == "" then axlUIWPrint(form "\307\353\312\344\310\353\305\344\326\303\303\373\263\306\241\243") else
            newProfile = list(name if(rexMatchp("^save_" field) then axlVisibleGet() else cadr(profile)))
            for(i 0 max(9 length(xkViewProfiles)-1)
              profiles = append1(profiles if(i == indexValue then newProfile else
                or(nth(i xkViewProfiles) list(sprintf(nil "P%d" i+1) nil)))))
            xkViewProfiles = profiles
            if(xkViewWriteProfiles() then
              axlUIWPrint(form strcat(if(rexMatchp("^save_" field) then "\322\321\261\243\264\346\243\272" else "\322\321\326\330\303\374\303\373\243\272") name))
            else axlUIWPrint(form "\305\344\326\303\316\304\274\376\261\243\264\346\312\247\260\334\241\243"))
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
        directory = axlDMDirectoryBrowse("." nil ?title "\321\241\324\361\277\342\304\277\302\274")
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
          axlUIWPrint(form sprintf(nil "%L \265\304\313\253\322\375\272\305\316\264\261\325\272\317\243\254\307\353\262\271\306\353\272\363\261\243\264\346\241\243" invalid))
        else
          foreach(setting settings
            value = buildString(foreach(mapcar directory cadr(setting) xkPathQuote(directory)) " ")
            result = errset(axlSetVariableFile(car(setting) value) t)
            unless(result && car(result) failed = cons(upperCase(car(setting)) failed)))
          if(failed then
            axlUIWPrint(form sprintf(nil "\261\243\264\346\312\247\260\334\243\272%L" failed))
          else axlUIWPrint(form "\277\342\302\267\276\266\322\321\261\243\264\346\262\242\301\242\274\264\311\372\320\247\241\243"))
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
      "HEADER \"A7 \320\336\270\304\277\342\302\267\276\266\"\t\nTILE\t\n")
    row = 1
    foreach(variable '("psmpath" "padpath" "devpath")
      definition = strcat(definition sprintf(nil
        "TEXT %L\t\nTLOC 2 %d\t\nENDTEXT\t\nFIELD %s\t\nFLOC 2 %d\t\nSTRFILLIN 90 4096\t\nENDFIELD\t\nFIELD browse_%s\t\nFLOC 94 %d\t\nMENUBUTTON \"\314\355\274\323\304\277\302\274\" 14 3\t\nENDFIELD\t\n"
        upperCase(variable) row variable row+3 variable row+3))
      row = row + 8
    )
    definition = strcat(definition
      "TEXT \"\277\311\314\356\320\264\266\340\270\366\304\277\302\274\243\273\272\254\277\325\270\361\265\304\304\277\302\274\323\303\313\253\322\375\272\305\260\374\316\247\241\243\"\t\nTLOC 2 26\t\nENDTEXT\t\n"
      "FIELD apply\t\nFLOC 90 30\t\nMENUBUTTON \"\261\243\264\346\311\350\326\303\" 18 3\t\nENDFIELD\t\nENDTILE\t\nENDFORM\t\n")
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

; UTF-8 authoring source. build-ui.py emits ASCII SKILL with GBK octal strings.
; Original tools are loaded separately; this wrapper composes their operations.

procedure(xkProductionSetup()
  when(axlDBGetDesign()
    ; Same setting applied when the original film_reorder.il is loaded.
    axlSetVariable("film_nosort" t)
    Autoart()
    Quick_ColorSet()
    axlUIWRedraw(nil)
    axlMsgPut("\320\241\277\252\271\244\276\337\317\344\243\272\271\342\273\346\241\242\262\343\265\376\321\325\311\253\323\353\305\305\320\362\311\350\326\303\315\352\263\311\241\243")
  )
)

axlCmdRegister("xk_production_setup" 'xkProductionSetup)

; Continuous numbering within the installed categories: A view, B text,
; C via editing, D checks. Internal command names retain compatibility.
xkViewTools = list(
  list("AI \303\374\301\356\270\250\326\372" "xk_ai" "\323\353 AI \266\324\273\260\243\254\266\250\316\273\306\367\274\376\272\315\265\367\323\303\322\321\260\262\327\260\271\244\276\337\243\273API \324\332\320\241\277\252\271\244\276\337\317\344\327\363\317\302\275\307\315\263\322\273\311\350\326\303\241\243")
  list("A1\243\272\324\252\274\376\301\320\261\355\323\353\266\250\316\273" "find component" "Ctrl+F \264\362\277\252\243\254\312\344\310\353\316\273\272\305\306\254\266\316\301\242\274\264\311\270\321\241\243\273\321\241\324\361\324\252\274\376\312\261\317\324\312\276\306\344\313\371\324\332\303\346\265\304 silk\241\242pin\241\242via\241\242etch \262\242\266\250\316\273\241\243")
  list("A2\243\272\317\326\323\320 DRC \344\257\300\300\323\353\266\250\316\273" "find drc" "\260\264\300\340\261\360\241\242\262\343\241\242\276\337\314\345\300\340\320\315\311\270\321\241\322\321\323\320 DRC\243\254\265\245\273\367\266\250\316\273\243\273\277\311\261\352\274\307\324\335\262\273\271\330\327\242\300\340\320\315\243\254\262\242\313\346\312\261\273\326\270\264\317\324\312\276\241\243")
  list("A3\243\272\277\354\313\331\307\320\273\273\270\361\265\343" "quick_grids" "\265\343\273\367 mil \273\362 mm \270\361\265\343\326\265\243\254\320\336\270\304\265\261\307\260\311\350\274\306\270\361\265\343\241\243")
  list("A4\243\272\277\354\313\331\307\320\273\273\262\343\317\324\312\276" "quick_display" "\312\256\270\366\327\324\266\250\322\345\317\324\312\276\305\344\326\303\243\254\304\254\310\317 P1\241\253P10\243\254\277\311\320\336\270\304\303\373\263\306\241\242\261\243\264\346\272\315\266\301\310\241\243\273ssq \315\352\325\373\260\346\241\242sq \303\324\304\343\260\346\241\243")
  list("A5\243\272mm\243\257mil \265\245\316\273\273\273\313\343" "conv" "\312\344\310\353 mil \273\362 mm \312\375\326\265\243\254\273\273\313\343\275\341\271\373\317\324\312\276\324\332\301\355\322\273\300\270\241\243")
  list("A6\243\272\272\270\305\314\323\353\277\327\276\266\270\337\301\301" "hps" "\301\320\261\355\260\346\243\272\321\241\324\361\272\270\305\314\303\373\263\306\273\362\277\327\276\266\243\254\270\337\301\301\266\324\323\246\322\375\275\305\272\315\271\375\277\327\243\273\317\340\271\330\262\343\320\350\277\311\274\373\241\243")
  list("A7\243\272\320\336\270\304\277\342\302\267\276\266" "xk_library_paths" "\321\241\324\361\273\362\314\356\320\264 PSMPATH\241\242PADPATH\241\242DEVPATH\243\254\261\243\264\346\272\363\301\242\274\264\311\372\320\247\241\243")
  list("A8\243\272\311\372\263\311\324\252\274\376\270\337\266\310\316\304\327\326" "show_height" "\266\300\301\242\266\301\310\241\324\252\274\376 PCB \267\342\327\260\270\337\266\310\312\364\320\324\243\254\311\372\263\311 HEIGHT_TEXT_TOP\243\257BOTTOM \270\337\266\310\316\304\327\326\243\273\326\330\270\264\324\313\320\320\311\276\263\375\262\242\326\330\275\250\325\342\301\275\262\343\316\304\327\326\241\243")
)

xkTextTools = list(
  list("B1\243\272\316\304\327\326\265\367\325\373\323\353\276\323\326\320" "tt" "\277\362\321\241\273\362\265\343\321\241\324\252\274\376\243\254\265\367\325\373\316\304\327\326\276\323\326\320\241\242\267\275\317\362\241\242\327\326\272\305\243\273\324\255\264\260\277\332\304\254\310\317\327\260\305\344\262\343\243\254\320\350\322\252\313\277\323\241\312\261\321\241\324\361 Silkscreen\241\243")
  list("B2\243\272\313\277\323\241\265\274\263\366\323\353\265\274\310\353" "xk_silk_io" "\317\310\277\362\321\241\324\252\274\376\273\362\313\277\323\241\324\252\313\330\243\254\265\343\273\367\265\274\263\366\272\363\321\241\324\361\261\243\264\346\302\267\276\266\243\273\275\366\265\274\263\366\321\241\326\320\267\266\316\247\241\243\324\255\260\346\265\274\310\353\273\341\275\342\263\375\271\314\266\250\262\242\314\346\273\273\316\304\274\376\313\371\301\320\262\343\310\253\262\277\313\277\323\241\241\243")
)

xkCheckTools = list(
  list("D2\243\272\316\264\311\310\263\366 SMD \322\375\275\305\274\354\262\351" "hl_nf" "\321\241\324\361\266\245\262\343\273\362\265\327\262\343\243\254\274\354\262\351\316\264\311\310\263\366\265\304 SMD \322\375\275\305\262\242\326\360\317\356\266\250\316\273\241\243")
  list("D3\243\272\272\270\305\314\323\353\327\337\317\337\274\344\276\340\274\354\262\351" "solder2line check" "\261\243\301\364\324\255\260\346\276\330\320\316\272\270\305\314\274\354\262\351\313\343\267\250\243\273\260\264\265\261\307\260\311\350\274\306\265\245\316\273\314\356\320\264\274\344\276\340\243\254\274\354\262\351\266\245\262\343\273\362\265\327\262\343\262\242\266\250\316\273\241\243")
  list("D4\243\272SMD \323\353\315\250\277\327\322\375\275\305\274\344\276\340\274\354\262\351" "quick_smd2thrp" "\274\354\262\351 SMD \324\252\274\376\323\353\266\324\303\346\315\250\277\327\322\375\275\305\265\304\274\344\276\340\243\254\326\247\263\326\307\260\272\363\266\250\316\273\243\273\304\254\310\317 120 mil\241\243")
  list("D5\243\272\310\261\311\331\316\375\270\340\277\252\264\260\274\354\262\351" "find_pin_no_past" "\324\255\260\346\274\323\303\334\275\305\261\276\243\254\311\372\263\311\310\261\311\331\316\375\270\340\277\252\264\260\265\304\322\375\275\305\261\250\270\346\241\243")
  list("D6\243\272\310\261\311\331\327\350\272\270\277\252\264\260\274\354\262\351" "find_pin_no_solder" "\324\255\260\346\274\323\303\334\275\305\261\276\243\254\311\372\263\311\310\261\311\331\327\350\272\270\277\252\264\260\265\304\322\375\275\305\261\250\270\346\241\243")
  list("D7\243\272\310\261\312\247\313\277\323\241\316\273\272\305\274\354\262\351" "Check_No_Refdes" "\324\313\320\320\272\363\326\261\275\323\317\324\312\276\262\242\270\337\301\301\310\261\311\331\313\277\323\241\316\273\272\305\265\304\324\252\274\376\243\254\327\324\266\257\264\362\277\252\274\354\262\351\261\250\270\346\243\273\275\341\271\373\261\243\301\364\324\332 no_refdes.log\241\243")
  list("D8\243\272\313\277\323\241\326\330\265\376\274\354\262\351\243\250\324\366\307\277\260\346\243\251" "ch_text_overlap" "\321\241\324\361\266\245\262\343\273\362\265\327\262\343\274\260\274\354\262\351\317\356\304\277\243\254\274\354\262\351\272\363\323\303\307\260\272\363\260\264\305\245\266\250\316\273\243\273\274\344\276\340\312\271\323\303\265\261\307\260\311\350\274\306\265\245\316\273\241\243")
  list("D9\243\272\313\277\323\241\316\273\272\305\275\273\262\346\274\354\262\351" "ch_cross" "\274\354\262\351\275\273\262\346\316\273\272\305\243\254\324\332 MANUFACTURING/REFDES TOP DRC\241\242BOTTOM DRC \262\343\311\372\263\311\261\352\274\307\241\243")
)

procedure(xkSkillToolboxAction(form)
  let((item command viewTool)
    cond(
      (and(form->curField == "tools" not(form->XkInitializing))
        item = form->curValueInt
        form->XkCommand = nil
        viewTool = assoc(item form->XkViewItems)
        axlFormSetFieldEditable(form "execute" nil)
        cond(
          (viewTool
            form->XkCommand = cadr(viewTool)
            axlFormSetField(form "description" caddr(viewTool))
            axlFormSetFieldEditable(form "execute" t)
          )
          (item == form->XkSetupItem
            form->XkCommand = "xk_production_setup"
            axlFormSetField(form "description" "\326\330\275\250\271\342\273\346\241\242\311\350\326\303\262\343\265\376\321\325\311\253\243\254\262\242\260\264\271\342\273\346\264\264\275\250\313\263\320\362\317\324\312\276\241\243")
            axlFormSetFieldEditable(form "execute" t)
          )
          (item == form->XkCheckItem
            form->XkCommand = "xk_dangling_check"
            axlFormSetField(form "description" "\267\326\322\263\274\354\262\351\241\242\266\250\316\273\241\242\313\242\320\302\272\315\311\276\263\375\320\374\277\325\317\337\241\242\271\375\277\327\274\260\271\302\265\272\241\243")
            axlFormSetFieldEditable(form "execute" t)
          )
          (item == form->XkViaNetItem
            form->XkCommand = "cvia"
            axlFormSetField(form "description" "\324\255\260\346 cvia\243\272\277\362\321\241\271\375\277\327\243\254\323\322\274\374 Done\243\254\324\331\321\241\324\361\304\277\261\352\315\370\302\347\243\273\314\370\271\375\271\314\266\250\271\375\277\327\241\243")
            axlFormSetFieldEditable(form "execute" t)
          )
          (member(item list(form->XkViewGroup form->XkTextGroup form->XkViaGroup form->XkCheckGroup))
            axlFormTreeViewSet(form "tools" 'TV_EXPAND item)
            axlFormSetField(form "description" "\325\271\277\252\272\363\321\241\324\361\271\244\276\337\243\254\324\331\265\343\273\367\326\264\320\320\241\243")
          )
          (t
            axlFormSetField(form "description" "\264\313\267\326\300\340\324\335\316\336\322\321\260\262\327\260\271\244\276\337\243\254\272\363\320\370\260\264\321\241\324\361\274\323\310\353\241\243")
          )
        )
      )
      (and(form->curField == "execute" form->XkCommand)
        if(axlDBGetDesign() then
          command = form->XkCommand
          axlShellPost(command)
        else
          axlUIWPrint(form "\307\353\317\310\264\362\277\252\260\345\316\304\274\376\241\243")
        )
      )
      (or(form->curField == "done" form->curField == "cancel")
        axlFormClose(form)
      )
    )
    t
  )
)

procedure(xkSkillToolboxNative()
  let((form definition)
    xkEnsureToolboxHelper()
    definition = strcat(
      "FILE_TYPE=FORM_DEFN VERSION=2\t\n"
      "FORM\t\n"
      "FIXED\t\n"
      "PORT 86 58\t\n"
      "HEADER \"\320\241\277\252 SKILL \271\244\276\337\317\344\"\t\n"
      "TILE\t\n"
      "TEXT \"\265\343\273\367\267\326\300\340\325\271\277\252\243\254\313\253\273\367\271\244\276\337\326\261\275\323\324\313\320\320\"\t\n"
      "TLOC 3 1\t\n"
      "ENDTEXT\t\n"
      "FIELD tools\t\n"
      "FLOC 3 4\t\n"
      "FSIZE 80 44\t\n"
      "TREEVIEW 80 44\t\n"
      "ENDFIELD\t\n"
      "TEXT\t\n"
      "TLOC 3 49\t\n"
      "INFO description 80\t\n"
      "ENDTEXT\t\n"
      "FIELD execute\t\n"
      "FLOC 54 53\t\n"
      "MENUBUTTON \"\326\264\320\320\" 12 3\t\n"
      "ENDFIELD\t\n"
      "ENDTILE\t\n"
      "ENDFORM\t\n"
    )
    ; A stable symbol makes repeated Alt+K expose the existing window.
    form = axlFormCreate('xkSkillToolboxForm
      list("xiaokai_skill" definition) '(c inner) 'xkSkillToolboxAction t)
    when(form
      form->XkInitializing = t
      form->XkCommand = nil
      form->XkViewGroup = axlFormTreeViewAddItem(form "tools" "\262\351\277\264\300\340" nil nil)
      form->XkViewItems = nil
      foreach(tool xkViewTools
        form->XkViewItems = append1(form->XkViewItems
          list(axlFormTreeViewAddItem(form "tools" car(tool) form->XkViewGroup nil)
            cadr(tool) caddr(tool)))
      )
      form->XkSetupItem = axlFormTreeViewAddItem(form "tools"
        "A9\243\272\322\273\274\374\311\350\326\303\271\342\273\346\323\353\262\343\265\376\321\325\311\253" form->XkViewGroup nil)
      form->XkTextGroup = axlFormTreeViewAddItem(form "tools" "\313\277\323\241\323\353\316\304\327\326\325\373\300\355" nil nil)
      foreach(tool xkTextTools
        form->XkViewItems = append1(form->XkViewItems
          list(axlFormTreeViewAddItem(form "tools" car(tool) form->XkTextGroup nil)
            cadr(tool) caddr(tool))))
      form->XkViaGroup = axlFormTreeViewAddItem(form "tools" "\271\375\277\327\323\353\327\337\317\337\320\336\270\304" nil nil)
      form->XkViaNetItem = axlFormTreeViewAddItem(form "tools"
        "C1\243\272\271\375\277\327\320\336\270\304\315\370\302\347" form->XkViaGroup nil)
      foreach(label '("\315\255\306\244\241\242\262\274\276\326\323\353\260\345\315\274\270\250\326\372" "\311\372\262\372\312\344\263\366\323\353\327\252\273\273")
        axlFormTreeViewAddItem(form "tools" label nil nil)
      )
      form->XkCheckGroup = axlFormTreeViewAddItem(form "tools" "\274\354\262\351\300\340\243\250Check\243\251" nil nil)
      form->XkCheckItem = axlFormTreeViewAddItem(form "tools"
        "D1\243\272\320\374\277\325\317\337\243\257\271\375\277\327\243\257\271\302\265\272\274\354\262\351\323\353\264\246\300\355" form->XkCheckGroup nil)
      foreach(tool xkCheckTools
        form->XkViewItems = append1(form->XkViewItems
          list(axlFormTreeViewAddItem(form "tools" car(tool) form->XkCheckGroup nil)
            cadr(tool) caddr(tool))))
      axlFormTreeViewSet(form "tools" 'TV_NOEDITLABEL nil)
      axlFormTreeViewSet(form "tools" 'TV_COLLAPSE_TOP nil)
      axlFormSetField(form "description" "\325\271\277\252\267\326\300\340\262\242\321\241\324\361\271\244\276\337\243\254\277\311\324\332\264\313\262\351\277\264\271\246\304\334\313\265\303\367\241\243")
      axlFormSetFieldEditable(form "execute" nil)
      axlFormDisplay(form)
      axlFormTreeViewSet(form "tools" 'TV_COLLAPSE_TOP nil)
      axlFormTreeViewSet(form "tools" 'TV_SELECTITEM nil)
      form->XkInitializing = nil
    )
  )
)

; The companion owns presentation; database commands remain in Allegro.
procedure(xkSkillToolbox()
  xkEnsureToolboxHelper()
  if(boundp('xkToolboxHotkeyProcess) && xkToolboxHotkeyProcess then
    ipcWriteProcess(xkToolboxHotkeyProcess "TOOLBOX\n")
  else
    xkSkillToolboxNative()
  )
)
axlCmdRegister("xk_skill" 'xkSkillToolbox ?cmdType "general")

unless(boundp('xkToolboxMenuAdded) xkToolboxMenuAdded = nil)

procedure(xkSelectedToolsMenu(menuName)
  let((anchor popup existing)
    when(or(menuName not(xkToolboxMenuAdded))
      ; A command placed directly on the menu bar does not dispatch on click.
      ; Use a real popup containing the same registered command as Alt+K.
      ; Reuse an existing popup command when this source or menu is reloaded.
      ; Deleting/reinserting a root leaves stale captions in Allegro's Qt bar.
      existing = axlUIMenuFind(nil "xk_skill")
      if(existing then
        xkToolboxMenuAdded = t
      else
        anchor = axlUIMenuFind(nil -1)
        when(anchor
          popup = axlUIMenuInsert(anchor 'popup "\320\241\277\252\271\244\276\337\317\344")
          when(popup
            xkToolboxMenuAdded = axlUIMenuInsert(popup "\264\362\277\252 SKILL \271\244\276\337\317\344\243\250Alt+K\243\251" "xk_skill")
            axlUIMenuInsert(popup 'end))))
    )
  )
)

axlTriggerClear('menu 'xkSelectedToolsMenu)
axlTriggerSet('menu 'xkSelectedToolsMenu)
; Also replace the old menu when upgrading an already-running session.
xkSelectedToolsMenu(nil)

procedure(xkToolboxCommandAllowed(command)
  member(command append(foreach(mapcar tool append(xkViewTools append(xkTextTools xkCheckTools)) cadr(tool))
    '("xk_production_setup" "cvia" "xk_dangling_check")))
)

procedure(xkToolboxHandleLine(line)
  cond(
      (rexMatchp("^AI_CONTEXT " line) xkAiContext(cadr(parseString(line " "))))
      (rexMatchp("^AI_CANCEL " line)
        when(boundp('xkAiRequest) && xkAiRequest == cadr(parseString(line " ")) xkAiRequest = nil))
      (rexMatchp("^AI_ACTION " line) xkAiAction(parseString(line " ")))
      (rexMatchp("^EXEC " line)
        let((command)
          command = substring(line 6)
          when(xkToolboxCommandAllowed(command)
            if(axlDBGetDesign() then axlShellPost(command)
              else axlMsgPut("\307\353\317\310\264\362\277\252\260\345\316\304\274\376\241\243")))
        )
      )
      (member(line '("FIND" "REFRESH_COMPONENTS")) xkFindComponent())
      (rexMatchp("^LOCATE " line) xkLocateComponent(atoi(cadr(parseString(line " ")))))
      (line == "REFRESH_DRC" xkFindDrc())
      (rexMatchp("^LOCATE_DRC " line) xkLocateDrc(atoi(cadr(parseString(line " ")))))
      (line == "DRCS_LOADED" axlTempFileRemove(xkDrcDataFile))
      (line == "DRCS_FAILED" axlMsgPut("DRC \301\320\261\355\264\362\277\252\312\247\260\334\243\254\307\353\326\330\320\302\324\313\320\320\241\243"))
      (line == "COMPONENTS_LOADED" axlTempFileRemove(xkComponentDataFile))
      (line == "COMPONENTS_FAILED" axlMsgPut("\324\252\274\376\301\320\261\355\264\362\277\252\312\247\260\334\243\254\307\353\326\330\320\302\324\313\320\320\241\243"))
      (line == "OPEN" xkSkillToolbox())
      (line == "RUN"
        when(boundp('xkSkillToolboxForm) && xkSkillToolboxForm && xkSkillToolboxForm->XkCommand
          axlShellPost(xkSkillToolboxForm->XkCommand)
        )
      )
  )
)

procedure(xkAiOpen()
  xkEnsureToolboxHelper()
  when(boundp('xkToolboxHotkeyProcess) && xkToolboxHotkeyProcess
    ipcWriteProcess(xkToolboxHotkeyProcess "AI_OPEN\n"))
)
axlCmdRegister("xk_ai" 'xkAiOpen ?cmdType "general")

procedure(xkAiContext(request)
  let((port names)
    xkAiRequest = nil
    if(axlDBGetDesign() then
      xkAiDesign = axlDBGetDesign()
      foreach(component xkAiDesign->components
        when(component->symbol names = cons(component->name names)))
      xkAiNames = sort(names 'alphalessp)
      xkAiRequest = request
      unless(boundp('xkAiDataFile) xkAiDataFile = axlTempFile())
      port = outfile(xkAiDataFile)
      if(port then
        fprintf(port "%s\n" xkAiDesign->name)
        foreach(name xkAiNames fprintf(port "%s\n" name))
        close(port)
        ipcWriteProcess(xkToolboxHotkeyProcess strcat("AI_CONTEXT_FILE " request " " xkAiDataFile "\n"))
      else
        ipcWriteProcess(xkToolboxHotkeyProcess strcat("AI_RESULT " request " FAILED\n")))
    else
      ipcWriteProcess(xkToolboxHotkeyProcess strcat("AI_RESULT " request " FAILED\n")))
  )
)
procedure(xkAiAction(fields)
  let((request action argument command result name component currentNames)
    request = cadr(fields) action = caddr(fields) argument = cadddr(fields)
    when(boundp('xkAiRequest) && xkAiRequest == request && axlDBGetDesign() == xkAiDesign
      xkAiRequest = nil
      if(action == "locate" then
        foreach(c axlDBGetDesign()->components when(c->symbol currentNames = cons(c->name currentNames)))
        when(sort(currentNames 'alphalessp) == xkAiNames && atoi(argument) >= 0 && atoi(argument) < length(xkAiNames)
          name = nth(atoi(argument) xkAiNames)
          component = car(setof(c axlDBGetDesign()->components c->name == name))
          when(component && component->symbol
            xkComponentNames = xkAiNames
            result = errset(xkLocateComponent(atoi(argument)) t)))
      else
        when(action == "open_tool"
          command = cadr(assoc(argument list(
            list("components" "find component") list("drc" "find drc") list("grid" "quick_grids")
            list("display" "quick_display") list("convert" "conv") list("pads" "hps")
            list("library" "xk_library_paths") list("height" "show_height")
            list("production" "xk_production_setup") list("via" "cvia") list("dangling" "xk_dangling_check"))))
          when(command result = errset(axlShellPost(command) t))))
    )
    ipcWriteProcess(xkToolboxHotkeyProcess strcat("AI_RESULT " request if(result then " OK\n" else " FAILED\n")))
  )
)

; IPC may deliver several lines together or split one line across callbacks.
; Catch each request independently so one failed action leaves dispatch usable.
unless(boundp('xkToolboxInputBuffer) xkToolboxInputBuffer = "")
procedure(xkToolboxHotkeyData(processId data)
  let((lines complete)
    when(stringp(data) && data != ""
      xkToolboxInputBuffer = strcat(xkToolboxInputBuffer data)
      complete = substring(xkToolboxInputBuffer strlen(xkToolboxInputBuffer) 1) == "\n"
      lines = parseString(xkToolboxInputBuffer "\n")
      xkToolboxInputBuffer = if(complete then "" else car(last(lines)))
      unless(complete lines = reverse(cdr(reverse(lines))))
      foreach(line lines
        unless(errset(xkToolboxHandleLine(car(parseString(line "\r"))) t)
          axlMsgPut("\264\313\317\356\262\331\327\367\316\264\315\352\263\311\243\254\277\311\274\314\320\370\321\241\324\361\271\244\276\337\243\273\264\355\316\363\317\352\307\351\274\373\303\374\301\356\264\260\277\332\241\243")))
    )
    t
  )
)

procedure(xkEnsureToolboxHelper()
  let((alive)
    when(boundp('xkAllegroInstallRoot)
      when(boundp('xkToolboxHotkeyProcess) && xkToolboxHotkeyProcess
        alive = errset(ipcIsAliveProcess(xkToolboxHotkeyProcess) nil))
      unless(alive && car(alive)
        xkToolboxInputBuffer = ""
        xkToolboxHotkeyProcess = ipcBeginProcess(
          strcat("\"" xkAllegroInstallRoot "/xiaokaiAllegroHotkey.exe\"")
          "" 'xkToolboxHotkeyData nil nil))
    )
  )
)

; HOME/pcbenv is the installation location. The installer supplies this path
; explicitly so custom Cadence HOME locations work as well.
xkEnsureToolboxHelper()
axlMsgPut("Xiaokai SKILL toolbox: Alt+K / xk_skill. Original tools loaded.")
