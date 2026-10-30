; C3 retains the original selected-area/target-width check.
procedure(xkC3CheckBox(box target)
 let((enabled buttons drcs segments errors x y layer drc segment keys)
  enabled=axlGetFindFilter(nil)
  buttons=axlGetFindFilter(t)
  errors=0
  axlClearSelSet()
  axlSetFindFilter(?enabled '("noall" "drcs") ?onButtons '("noall" "drcs"))
  axlSetFindFilter(?enabled '("noall" "clinesegs") ?onButtons '("noall" "clinesegs"))
  axlSingleSelectBox(box)
  segments=axlGetSelSet()
  foreach(segment segments
   x=(caar(segment->startEnd)+caadr(segment->startEnd))/2.0
   y=(cadar(segment->startEnd)+cadadr(segment->startEnd))/2.0
   layer=strcat("DRC ERROR CLASS/" cadr(parseString(segment->layer "/")))
   keys=cons(list(layer list(x y)) keys)
   axlVisibleLayer(layer t))
  axlClearSelSet()
  axlVisibleUpdate(t)
  axlSetFindFilter(?enabled '("noall" "drcs") ?onButtons '("noall" "drcs"))
  ; Crossing segments can have their midpoint outside the selection box.
  ; Match old markers to the selected segments by layer and midpoint.
  axlAddSelectAll()
  drcs=axlGetSelSet()
  foreach(drc drcs
   when(drc->source == "User defined line width" && member(list(drc->layer drc->xy) keys)
    axlDeleteObject(drc)))
  axlClearSelSet()
  foreach(segment segments
   when(abs(segment->width-target)>axlMKSConvert(0.0001 "mils")
    x=(caar(segment->startEnd)+caadr(segment->startEnd))/2.0
    y=(cadar(segment->startEnd)+cadadr(segment->startEnd))/2.0
    layer=strcat("DRC ERROR CLASS/" cadr(parseString(segment->layer "/")))
    axlDBCreateExternalDRC("User defined line width" list(x y) layer list(segment) nil sprintf(nil "%f" segment->width))
    axlVisibleLayer(layer t)
    errors++))
  axlClearSelSet()
  axlSetFindFilter(?enabled enabled ?onButtons buttons)
  axlVisibleUpdate(t)
  axlMsgPut("C3：发现 %d 段线宽不符；目标 %g %s。" errors target axlGetParam("paramDesign")->units)
  errors
 ))
procedure(xkC3Width()
 prog((value target box)
  value=axlEnterString(?prompts list(strcat("输入区域内目标线宽（" axlGetParam("paramDesign")->units "）")))
  unless(value return(nil))
  unless(rexMatchp("^[0-9]+[.]?[0-9]*$" value)
   axlMsgPut("请输入大于零的线宽数值。") return(nil))
  target=atof(value)
  unless(target>0 axlMsgPut("线宽必须大于零。") return(nil))
  box=axlEnterBox(?prompts list("框选需要检查的走线区域；取消退出。"))
  unless(box return(nil))
  xkC3CheckBox(box target)
 ))
axlCmdRegister("checkWidth" 'xkC3Width)
