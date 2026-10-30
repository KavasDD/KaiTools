; UTF-8 authoring source. build-ui.py emits ASCII SKILL with GBK octal strings.
; Original tools are loaded separately; this wrapper composes their operations.

procedure(xkProductionSetup()
  when(axlDBGetDesign()
    ; Same setting applied when the original film_reorder.il is loaded.
    axlSetVariable("film_nosort" t)
    Autoart()
    Quick_ColorSet()
    axlUIWRedraw(nil)
    axlMsgPut("小开工具箱：光绘、层叠颜色与排序设置完成。")
  )
)

axlCmdRegister("xk_production_setup" 'xkProductionSetup)

; Continuous numbering within the installed categories: A view, B text,
; C via editing, D checks. Internal command names retain compatibility.
xkViewTools = list(
  list("AI 命令辅助" "xk_ai" "与 AI 对话，定位器件和调用已安装工具；API 在小开工具箱左下角统一设置。")
  list("A1：元件列表与定位" "find component" "Ctrl+F 打开，输入位号片段立即筛选；选择元件时显示其所在面的 silk、pin、via、etch 并定位。")
  list("A2：现有 DRC 浏览与定位" "find drc" "按类别、层、具体类型筛选已有 DRC，单击定位；可标记暂不关注类型，并随时恢复显示。")
  list("A3：快速切换格点" "quick_grids" "点击 mil 或 mm 格点值，修改当前设计格点。")
  list("A4：快速切换层显示" "quick_display" "十个自定义显示配置，默认 P1～P10，可修改名称、保存和读取；ssq 完整版、sq 迷你版。")
  list("A5：mm／mil 单位换算" "conv" "输入 mil 或 mm 数值，换算结果显示在另一栏。")
  list("A6：焊盘与孔径高亮" "hps" "列表版：选择焊盘名称或孔径，高亮对应引脚和过孔；相关层需可见。")
  list("A7：修改库路径" "xk_library_paths" "选择或填写 PSMPATH、PADPATH、DEVPATH，保存后立即生效。")
  list("A8：生成元件高度文字" "show_height" "独立读取元件 PCB 封装高度属性，生成 HEIGHT_TEXT_TOP／BOTTOM 高度文字；重复运行删除并重建这两层文字。")
)

xkTextTools = list(
  list("B1：文字调整与居中" "tt" "框选或点选元件，调整文字居中、方向、字号；原窗口默认装配层，需要丝印时选择 Silkscreen。")
  list("B2：丝印导出与导入" "xk_silk_io" "先框选元件或丝印元素，点击导出后选择保存路径；仅导出选中范围。原版导入会解除固定并替换文件所列层全部丝印。")
)

xkCheckTools = list(
  list("D2：未扇出 SMD 引脚检查" "hl_nf" "选择顶层或底层，检查未扇出的 SMD 引脚并逐项定位。")
  list("D3：焊盘与走线间距检查" "solder2line check" "保留原版矩形焊盘检查算法；按当前设计单位填写间距，检查顶层或底层并定位。")
  list("D4：SMD 与通孔引脚间距检查" "quick_smd2thrp" "检查 SMD 元件与对面通孔引脚的间距，支持前后定位；默认 120 mil。")
  list("D5：缺少锡膏开窗检查" "find_pin_no_past" "原版加密脚本，生成缺少锡膏开窗的引脚报告。")
  list("D6：缺少阻焊开窗检查" "find_pin_no_solder" "原版加密脚本，生成缺少阻焊开窗的引脚报告。")
  list("D7：缺失丝印位号检查" "Check_No_Refdes" "运行后直接显示并高亮缺少丝印位号的元件，自动打开检查报告；结果保留在 no_refdes.log。")
  list("D8：丝印重叠检查（增强版）" "ch_text_overlap" "选择顶层或底层及检查项目，检查后用前后按钮定位；间距使用当前设计单位。")
  list("D9：丝印位号交叉检查" "ch_cross" "检查交叉位号，在 MANUFACTURING/REFDES TOP DRC、BOTTOM DRC 层生成标记。")
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
            axlFormSetField(form "description" "重建光绘、设置层叠颜色，并按光绘创建顺序显示。")
            axlFormSetFieldEditable(form "execute" t)
          )
          (item == form->XkCheckItem
            form->XkCommand = "xk_dangling_check"
            axlFormSetField(form "description" "分页检查、定位、刷新和删除悬空线、过孔及孤岛。")
            axlFormSetFieldEditable(form "execute" t)
          )
          (item == form->XkViaNetItem
            form->XkCommand = "cvia"
            axlFormSetField(form "description" "原版 cvia：框选过孔，右键 Done，再选择目标网络；跳过固定过孔。")
            axlFormSetFieldEditable(form "execute" t)
          )
          (member(item list(form->XkViewGroup form->XkTextGroup form->XkViaGroup form->XkCheckGroup))
            axlFormTreeViewSet(form "tools" 'TV_EXPAND item)
            axlFormSetField(form "description" "展开后选择工具，再点击执行。")
          )
          (t
            axlFormSetField(form "description" "此分类暂无已安装工具，后续按选择加入。")
          )
        )
      )
      (and(form->curField == "execute" form->XkCommand)
        if(axlDBGetDesign() then
          command = form->XkCommand
          axlShellPost(command)
        else
          axlUIWPrint(form "请先打开板文件。")
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
      "HEADER \"小开 SKILL 工具箱\"\t\n"
      "TILE\t\n"
      "TEXT \"点击分类展开，双击工具直接运行\"\t\n"
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
      "MENUBUTTON \"执行\" 12 3\t\n"
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
      form->XkViewGroup = axlFormTreeViewAddItem(form "tools" "查看类" nil nil)
      form->XkViewItems = nil
      foreach(tool xkViewTools
        form->XkViewItems = append1(form->XkViewItems
          list(axlFormTreeViewAddItem(form "tools" car(tool) form->XkViewGroup nil)
            cadr(tool) caddr(tool)))
      )
      form->XkSetupItem = axlFormTreeViewAddItem(form "tools"
        "A9：一键设置光绘与层叠颜色" form->XkViewGroup nil)
      form->XkTextGroup = axlFormTreeViewAddItem(form "tools" "丝印与文字整理" nil nil)
      foreach(tool xkTextTools
        form->XkViewItems = append1(form->XkViewItems
          list(axlFormTreeViewAddItem(form "tools" car(tool) form->XkTextGroup nil)
            cadr(tool) caddr(tool))))
      form->XkViaGroup = axlFormTreeViewAddItem(form "tools" "过孔与走线修改" nil nil)
      form->XkViaNetItem = axlFormTreeViewAddItem(form "tools"
        "C1：过孔修改网络" form->XkViaGroup nil)
      foreach(label '("铜皮、布局与板图辅助" "生产输出与转换")
        axlFormTreeViewAddItem(form "tools" label nil nil)
      )
      form->XkCheckGroup = axlFormTreeViewAddItem(form "tools" "检查类（Check）" nil nil)
      form->XkCheckItem = axlFormTreeViewAddItem(form "tools"
        "D1：悬空线／过孔／孤岛检查与处理" form->XkCheckGroup nil)
      foreach(tool xkCheckTools
        form->XkViewItems = append1(form->XkViewItems
          list(axlFormTreeViewAddItem(form "tools" car(tool) form->XkCheckGroup nil)
            cadr(tool) caddr(tool))))
      axlFormTreeViewSet(form "tools" 'TV_NOEDITLABEL nil)
      axlFormTreeViewSet(form "tools" 'TV_COLLAPSE_TOP nil)
      axlFormSetField(form "description" "展开分类并选择工具，可在此查看功能说明。")
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
          popup = axlUIMenuInsert(anchor 'popup "小开工具箱")
          when(popup
            xkToolboxMenuAdded = axlUIMenuInsert(popup "打开 SKILL 工具箱（Alt+K）" "xk_skill")
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
              else axlMsgPut("请先打开板文件。")))
        )
      )
      (member(line '("FIND" "REFRESH_COMPONENTS")) xkFindComponent())
      (rexMatchp("^LOCATE " line) xkLocateComponent(atoi(cadr(parseString(line " ")))))
      (line == "REFRESH_DRC" xkFindDrc())
      (rexMatchp("^LOCATE_DRC " line) xkLocateDrc(atoi(cadr(parseString(line " ")))))
      (line == "DRCS_LOADED" axlTempFileRemove(xkDrcDataFile))
      (line == "DRCS_FAILED" axlMsgPut("DRC 列表打开失败，请重新运行。"))
      (line == "COMPONENTS_LOADED" axlTempFileRemove(xkComponentDataFile))
      (line == "COMPONENTS_FAILED" axlMsgPut("元件列表打开失败，请重新运行。"))
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
          axlMsgPut("此项操作未完成，可继续选择工具；错误详情见命令窗口。")))
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
