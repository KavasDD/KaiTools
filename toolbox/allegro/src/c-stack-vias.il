; C4 preserves the original square search about each via center.
procedure(xkC4Check(distance)
 let((enabled buttons visibility vias candidates p box report count via)
  enabled=axlGetFindFilter(nil) buttons=axlGetFindFilter(t)
  visibility=axlVisibleGet()
  axlClearSelSet()
  axlVisibleDesign(nil)
  axlVisibleLayer("VIA CLASS/TOP" t)
  axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
  axlVisibleUpdate(t)
  axlSetFindFilter(?enabled '("noall" "vias") ?onButtons '("noall" "vias"))
  vias=axlGetSelSet(axlAddSelectAll())
  ; Allegro caches numeric attributes across drawing-unit changes.
  foreach(via vias axlDBRefreshId(via))
  foreach(via vias
   p=via->xy
   box=list(list(car(p)-distance cadr(p)-distance) list(car(p)+distance cadr(p)+distance))
   axlClearSelSet()
   axlAddSelectBox(box)
   when(axlGetSelSetCount()>1 candidates=cons(via candidates)))
  report=outfile("Stack_Vias.txt")
  when(report
   fprintf(report "C4：近邻过孔候选报告\n中心方框半宽：%g %s\n保留原版中心方框筛选；候选不等于电气违规。\n\n焊盘名称\t坐标\n" distance axlGetParam("paramDesign")->units)
   foreach(via candidates fprintf(report "%L\t%L\n" via->name via->xy))
   close(report))
  count=length(candidates)
  axlClearSelSet()
  axlSetFindFilter(?enabled enabled ?onButtons buttons)
  axlVisibleSet(visibility)
  axlVisibleUpdate(t)
  axlMsgPut("C4：发现 %d 个近邻过孔候选。" count)
  when(report axlUIViewFileCreate("Stack_Vias.txt" "C4：近邻过孔检查报告" nil))
  count
 ))
procedure(xkC4Action(form)
 case(form->curField
  ("check" let((distance) distance=axlFormGetField(form "distance")
    when(distance>0 xkC4Check(distance))))
  (("done" "cancel") unless(form->doneState==3 axlFormClose(form)))) t)
procedure(xkC4Open()
 let((form definition)
  definition=strcat(
   "FILE_TYPE=FORM_DEFN VERSION=2\t\nFORM\t\nFIXED\t\nPORT 66 19\t\nHEADER \"C4：近邻过孔检查\"\t\nTILE\t\n"
   "TEXT \"中心方框半宽（当前设计单位）\"\t\nTLOC 2 1\t\nENDTEXT\t\n"
   "FIELD distance\t\nFLOC 2 5\t\nREALFILLIN 20 20\t\nREALMIN 0\t\nENDFIELD\t\n"
   "FIELD units\t\nFLOC 46 5\t\nSTRFILLIN 16 16\t\nENDFIELD\t\n"
   "TEXT \"默认 8 mil；筛选近邻候选，请复核实际间距。\"\t\nTLOC 2 9\t\nENDTEXT\t\n"
   "FIELD check\t\nFLOC 2 13\t\nMENUBUTTON \"检查并打开报告\" 30 3\t\nENDFIELD\t\nENDTILE\t\nENDFORM\t\n")
  form=axlFormCreate((gensym) list("xkC4" definition) '(e inner) 'xkC4Action t)
  when(form
   axlFormSetField(form "distance" axlMKSConvert(8 "mils"))
   axlFormSetField(form "units" axlGetParam("paramDesign")->units)
   axlFormSetFieldEditable(form "units" nil)
   axlFormDisplay(form))
 ))
axlCmdRegister("sv" 'xkC4Open)
