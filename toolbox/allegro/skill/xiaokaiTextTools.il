; B7/B8 shelved at the user's request. Keep legacy commands harmless.
procedure(xkTextToolsDeferred()
  axlMsgPut("B7\241\242B8 \322\321\324\335\312\261\270\351\326\303\243\254\272\363\320\370\324\331\264\246\300\355\241\243")
  nil)
axlCmdRegister("text_rotate" 'xkTextToolsDeferred)
axlCmdRegister("quick_textset" 'xkTextToolsDeferred)

; B2 selected export uses the upstream t/l/c/a record format. Import is upstream.
procedure(xkSilkOwner(obj)
  let((owner ref)
    owner=obj
    while(owner && not(ref)
      when(owner->objType == "symbol" ref=owner->refdes)
      owner=owner->parent)
    if(ref then ref else "nil")))

procedure(xkSilkSelectedObjects(selected)
  let((objects queue obj)
    queue=copy(selected)
    while(queue
      obj=car(queue) queue=cdr(queue)
      when(axlDBRefreshId(obj)
        cond(
          (obj->objType == "component" queue=cons(obj->symbol queue))
          (obj->objType == "symbol" queue=append(obj->children queue))
          (obj->objType == "path" queue=append(obj->segments queue))
          (member(obj->objType '("text" "line" "arc"))
            when(member(obj->layer '("REF DES/SILKSCREEN_TOP" "REF DES/SILKSCREEN_BOTTOM"
                "PACKAGE GEOMETRY/SILKSCREEN_TOP" "PACKAGE GEOMETRY/SILKSCREEN_BOTTOM"
                "BOARD GEOMETRY/SILKSCREEN_TOP" "BOARD GEOMETRY/SILKSCREEN_BOTTOM"))
              unless(member(obj objects) objects=cons(obj objects)))))))
    reverse(objects)))

procedure(xkSilkRecord(obj)
  let((owner layer start end)
    owner=xkSilkOwner(obj) layer=obj->layer
    case(obj->objType
      ("text" sprintf(nil "t!%s!%s!%s!%f!%f!%s!%f!%L!%s\n"
        owner obj->text layer car(obj->xy) cadr(obj->xy) obj->textBlock obj->rotation obj->isMirrored obj->justify))
      ("line"
        start=car(obj->startEnd) end=cadr(obj->startEnd)
        sprintf(nil "l!%s!%s!%f!%f!%f!%f!%f\n"
          owner layer car(start) cadr(start) car(end) cadr(end) obj->width))
      ("arc"
        if(obj->isCircle then
          sprintf(nil "c!%s!%s!%f!%f!%f!%f\n" owner layer car(obj->xy) cadr(obj->xy) obj->radius obj->width)
        else
          start=car(obj->startEnd) end=cadr(obj->startEnd)
          sprintf(nil "a!%s!%s!%f!%f!%f!%f!%L!%L!%f!%f!%f\n"
            owner layer car(start) cadr(start) car(end) cadr(end) obj->isCircle obj->isClockwise
            car(obj->xy) cadr(obj->xy) obj->width))))))

procedure(xkSilkExportFile(file selected)
  let((objects records port)
    objects=xkSilkSelectedObjects(selected)
    unless(objects error("B2\243\272\321\241\326\320\267\266\316\247\304\332\303\273\323\320\313\277\323\241\316\304\327\326\273\362\317\337\314\365\243\254\307\353\317\310\277\362\321\241\324\252\274\376\273\362\313\277\323\241\324\252\313\330\241\243"))
    ; Assemble and validate all records before opening the chosen destination.
    foreach(obj objects
      when(index(xkSilkOwner(obj) "!") || (obj->objType == "text" &&
          (index(obj->text "!") || index(obj->text "\n") || index(obj->text "\r")))
        error("B2\243\272\316\304\327\326\260\374\272\254\324\255\260\346\270\361\312\275\262\273\326\247\263\326\265\304\267\326\270\364\267\373\243\254\316\264\265\274\263\366\241\243"))
      records=cons(xkSilkRecord(obj) records))
    port=outfile(file)
    unless(port error("B2\243\272\316\336\267\250\320\264\310\353\313\371\321\241\302\267\276\266\241\243"))
    unwindProtect(
      progn(
        fprintf(port "X_EXPORT SILKSCREEN\n")
        fprintf(port "REF DES/SILKSCREEN_TOP!PACKAGE GEOMETRY/SILKSCREEN_TOP!BOARD GEOMETRY/SILKSCREEN_TOP!REF DES/SILKSCREEN_BOTTOM!PACKAGE GEOMETRY/SILKSCREEN_BOTTOM!BOARD GEOMETRY/SILKSCREEN_BOTTOM\n")
        foreach(record reverse(records) fprintf(port "%s" record)))
      close(port))
    axlMsgPut("B2\243\272\322\321\265\274\263\366\321\241\326\320\267\266\316\247\243\254\271\262 %d \314\365\274\307\302\274\243\272%s" length(records) file)
    length(records)))

procedure(xkSilkExport(selected)
  let((file)
    unless(xkSilkSelectedObjects(selected)
      error("B2\243\272\307\353\317\310\324\332\260\345\315\274\326\320\277\362\321\241\324\252\274\376\273\362\313\277\323\241\324\252\313\330\243\254\324\331\265\343\273\367\265\274\263\366\241\243"))
    file=axlDMFileBrowse(nil t ?title "B2 \265\274\263\366\321\241\326\320\267\266\316\247\265\304\313\277\323\241"
      ?defaultName "selected.silk" ?optFilters "\313\277\323\241\316\304\274\376 (*.silk)|*.silk")
    when(file xkSilkExportFile(file selected))))

procedure(xkSilkUnfixAll()
  let((fixedCount obj)
    fixedCount = axlDBDeletePropAll("FIXED")
    ; Private fixed flags are distinct from the public FIXED property.
    when(axlDBGetDesign()->module
      axlDBDeleteProp(axlDBGetDesign()->module "FIXED_PRIVATE"))
    when(axlDBGetDesign()->symbols
      axlDBDeleteProp(axlDBGetDesign()->symbols "FIXED_PRIVATE"))
    axlClearSelSet()
    axlMsgPut("B2\243\272\322\321\310\253\262\277\275\342\263\375\271\314\266\250\243\254\322\306\263\375 %L \270\366 FIXED \312\364\320\324\241\243" fixedCount)
    fixedCount
  )
)

procedure(xkSilkImportFile(file)
  let((port header script result)
    ; Validate before changing FIXED flags. No mutation when cancelled.
    unless(stringp(file) && isFile(file)
      error("B2\243\272\307\353\321\241\324\361\322\321\323\320\265\304\313\277\323\241\316\304\274\376\241\243"))
    when(index(file "\n") || index(file "\r") || index(file "\"")
      error("B2\243\272\316\304\274\376\302\267\276\266\260\374\272\254\262\273\326\247\263\326\265\304\327\326\267\373\241\243"))
    port = infile(file)
    gets(header port)
    close(port)
    unless(car(parseString(header "\r\n")) == "X_EXPORT SILKSCREEN"
      error("B2\243\272\316\304\274\376\262\273\312\307\324\255\260\346\271\244\276\337\265\274\263\366\265\304\313\277\323\241\270\361\312\275\241\243"))
    ; Native import asks for the file through fillin. Replay keeps its algorithm.
    script = strcat(axlTempFile() ".scr")
    port = outfile(script)
    unless(port error("B2\243\272\316\336\267\250\275\250\301\242\265\274\310\353\275\305\261\276\241\243"))
    fprintf(port "version 17.4\nsilkin\nfillin \"%s\"\n" file)
    close(port)
    result = errset(xkSilkUnfixAll() t)
    unless(result error("B2\243\272\275\342\263\375\271\314\266\250\316\264\315\352\263\311\243\254\316\264\306\364\266\257\265\274\310\353\241\243"))
    axlShellPost(strcat("replay \"" script "\""))
    t
  )
)

procedure(xkSilkImport()
  let((file)
    file = axlDMFileBrowse(nil nil ?title "B2 \324\255\260\346\265\274\310\353\243\272\275\342\263\375\271\314\266\250\262\242\314\346\273\273\313\371\301\320\262\343\310\253\262\277\313\277\323\241"
      ?optFilters "\313\277\323\241\316\304\274\376 (*.silk)|*.silk")
    when(file
      when(axlUIConfirm("\324\255\260\346\265\274\310\353\273\341\317\310\310\253\262\277\275\342\263\375\271\314\266\250\243\254\324\331\314\346\273\273\316\304\274\376\313\371\301\320\262\343\265\304\310\253\262\277\276\311\313\277\323\241\241\243\276\326\262\277\265\274\263\366\316\304\274\376\262\273\304\334\273\326\270\264\306\344\313\374\324\252\274\376\265\304\313\277\323\241\241\243\274\314\320\370\265\274\310\353\243\277")
        xkSilkImportFile(file)))
  )
)
axlCmdRegister("xk_silk_import" 'xkSilkImport)

procedure(xkSilkIoAction(form)
  cond(
    (form->curField == "export"
      let((selected)
        selected=axlGetSelSet()
        unless(selected
          when(form->XkDesign == axlDBGetDesign() selected=form->XkSelected))
        errset(xkSilkExport(selected) t)))
    (form->curField == "import" axlShellPost("xk_silk_import"))
    (member(form->curField '("done" "cancel")) axlFormClose(form))
  )
  t
)

procedure(xkSilkIo()
  let((definition form)
    definition = strcat(
      "FILE_TYPE=FORM_DEFN VERSION=2\t\nFORM\t\nFIXED\t\nPORT 120 20\t\n"
      "HEADER \"B2 \313\277\323\241\265\274\263\366\323\353\265\274\310\353\"\t\nTILE\t\n"
      "TEXT \"\265\274\263\366\243\272\317\310\277\362\321\241\324\252\274\376\273\362\313\277\323\241\324\252\313\330\243\254\324\331\321\241\324\361\261\243\264\346\302\267\276\266\241\243\"\t\nTLOC 3 2\t\nENDTEXT\t\n"
      "TEXT \"\324\255\260\346\265\274\310\353\243\272\310\253\262\277\275\342\263\375\271\314\266\250\243\254\314\346\273\273\316\304\274\376\313\371\301\320\262\343\265\304\310\253\262\277\313\277\323\241\241\243\"\t\nTLOC 3 5\t\nENDTEXT\t\n"
      "TEXT \"\276\326\262\277\265\274\263\366\316\304\274\376\262\273\304\334\273\326\270\264\306\344\313\374\324\252\274\376\313\277\323\241\243\273\265\274\310\353\307\260\307\353\310\267\310\317\316\304\274\376\267\266\316\247\241\243\"\t\nTLOC 3 8\t\nENDTEXT\t\n"
      "FIELD export\t\nFLOC 3 13\t\nMENUBUTTON \"\265\274\263\366\313\277\323\241\" 20 3\t\nENDFIELD\t\n"
      "FIELD import\t\nFLOC 28 13\t\nMENUBUTTON \"\310\253\262\277\275\342\263\375\271\314\266\250\262\242\265\274\310\353\" 40 3\t\nENDFIELD\t\n"
      "ENDTILE\t\nENDFORM\t\n")
    form = axlFormCreate('xkSilkIoForm list("xiaokai_silk_io" definition)
      '(c inner) 'xkSilkIoAction t)
    when(form
      form->XkDesign=axlDBGetDesign()
      form->XkSelected=axlGetSelSet()
      axlFormDisplay(form))
  )
)
axlCmdRegister("xk_silk_io" 'xkSilkIo)
