; B7/B8 shelved at the user's request. Keep legacy commands harmless.
procedure(xkTextToolsDeferred()
  axlMsgPut("B7、B8 已暂时搁置，后续再处理。")
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
    unless(objects error("B2：选中范围内没有丝印文字或线条，请先框选元件或丝印元素。"))
    ; Assemble and validate all records before opening the chosen destination.
    foreach(obj objects
      when(index(xkSilkOwner(obj) "!") || (obj->objType == "text" &&
          (index(obj->text "!") || index(obj->text "\n") || index(obj->text "\r")))
        error("B2：文字包含原版格式不支持的分隔符，未导出。"))
      records=cons(xkSilkRecord(obj) records))
    port=outfile(file)
    unless(port error("B2：无法写入所选路径。"))
    unwindProtect(
      progn(
        fprintf(port "X_EXPORT SILKSCREEN\n")
        fprintf(port "REF DES/SILKSCREEN_TOP!PACKAGE GEOMETRY/SILKSCREEN_TOP!BOARD GEOMETRY/SILKSCREEN_TOP!REF DES/SILKSCREEN_BOTTOM!PACKAGE GEOMETRY/SILKSCREEN_BOTTOM!BOARD GEOMETRY/SILKSCREEN_BOTTOM\n")
        foreach(record reverse(records) fprintf(port "%s" record)))
      close(port))
    axlMsgPut("B2：已导出选中范围，共 %d 条记录：%s" length(records) file)
    length(records)))

procedure(xkSilkExport(selected)
  let((file)
    unless(xkSilkSelectedObjects(selected)
      error("B2：请先在板图中框选元件或丝印元素，再点击导出。"))
    file=axlDMFileBrowse(nil t ?title "B2 导出选中范围的丝印"
      ?defaultName "selected.silk" ?optFilters "丝印文件 (*.silk)|*.silk")
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
    axlMsgPut("B2：已全部解除固定，移除 %L 个 FIXED 属性。" fixedCount)
    fixedCount
  )
)

procedure(xkSilkImportFile(file)
  let((port header script result)
    ; Validate before changing FIXED flags. No mutation when cancelled.
    unless(stringp(file) && isFile(file)
      error("B2：请选择已有的丝印文件。"))
    when(index(file "\n") || index(file "\r") || index(file "\"")
      error("B2：文件路径包含不支持的字符。"))
    port = infile(file)
    gets(header port)
    close(port)
    unless(car(parseString(header "\r\n")) == "X_EXPORT SILKSCREEN"
      error("B2：文件不是原版工具导出的丝印格式。"))
    ; Native import asks for the file through fillin. Replay keeps its algorithm.
    script = strcat(axlTempFile() ".scr")
    port = outfile(script)
    unless(port error("B2：无法建立导入脚本。"))
    fprintf(port "version 17.4\nsilkin\nfillin \"%s\"\n" file)
    close(port)
    result = errset(xkSilkUnfixAll() t)
    unless(result error("B2：解除固定未完成，未启动导入。"))
    axlShellPost(strcat("replay \"" script "\""))
    t
  )
)

procedure(xkSilkImport()
  let((file)
    file = axlDMFileBrowse(nil nil ?title "B2 原版导入：解除固定并替换所列层全部丝印"
      ?optFilters "丝印文件 (*.silk)|*.silk")
    when(file
      when(axlUIConfirm("原版导入会先全部解除固定，再替换文件所列层的全部旧丝印。局部导出文件不能恢复其它元件的丝印。继续导入？")
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
      "HEADER \"B2 丝印导出与导入\"\t\nTILE\t\n"
      "TEXT \"导出：先框选元件或丝印元素，再选择保存路径。\"\t\nTLOC 3 2\t\nENDTEXT\t\n"
      "TEXT \"原版导入：全部解除固定，替换文件所列层的全部丝印。\"\t\nTLOC 3 5\t\nENDTEXT\t\n"
      "TEXT \"局部导出文件不能恢复其它元件丝印；导入前请确认文件范围。\"\t\nTLOC 3 8\t\nENDTEXT\t\n"
      "FIELD export\t\nFLOC 3 13\t\nMENUBUTTON \"导出丝印\" 20 3\t\nENDFIELD\t\n"
      "FIELD import\t\nFLOC 28 13\t\nMENUBUTTON \"全部解除固定并导入\" 40 3\t\nENDFIELD\t\n"
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
