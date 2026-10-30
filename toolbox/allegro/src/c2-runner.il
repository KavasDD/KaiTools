; Responsive execution of the upstream geometric predicates.
; Results are committed per completed net; cancelling never reports completion.
xkC2Busy=nil
procedure(xkC2Pulse(force)
 xkC2Work=xkC2Work+1
 when(force || mod(xkC2Work 256)==0
  axlMeterUpdate(if(xkC2Total>0 then fix(100.0*xkC2Done/xkC2Total) else 100)
   sprintf(nil "%d/%d  %s" xkC2Done xkC2Total xkC2Current)
   sprintf(nil "比较 %d 次；点停止或按 Esc 取消" xkC2Work))
  when(axlMeterIsCancelled() || axlCancelTest() xkC2Cancelled=t))
 xkC2Cancelled)

procedure(xkC2PathRecord(segments)
 let((left bottom right top points)
  foreach(segment segments
   points=segment->startEnd
   foreach(point points
    if(left==nil then left=car(point) right=left bottom=cadr(point) top=bottom
    else left=min(left car(point)) right=max(right car(point)) bottom=min(bottom cadr(point)) top=max(top cadr(point)))))
  list(segments left bottom right top)))

procedure(xkC2BoxesTouch(a b)
 nth(1 a)<=nth(3 b) && nth(3 a)>=nth(1 b) && nth(2 a)<=nth(4 b) && nth(4 a)>=nth(2 b))

procedure(xkC2Pair(first second)
 prog((score result position)
  score=0
  foreach(segmentA car(first)
   foreach(segmentB car(second)
    when(xkC2Pulse(nil) return(nil))
    result=xkC2__lgs_Is_Cross(segmentA segmentB)
    when(result!=0
     score=score+car(result) position=cadr(result)
     ; Original criterion is score > 1. Further comparisons cannot undo it.
     when(score>1 return(position)))))
  return(nil)))

procedure(xkC2LoopNet(paths)
 prog((records tailA tailB hits location)
  foreach(segments paths records=cons(xkC2PathRecord(segments) records))
  tailA=records
  while(tailA && !xkC2Cancelled
   tailB=cdr(tailA)
   while(tailB && !xkC2Cancelled
    unless(xkC2Pulse(nil)
     when(xkC2BoxesTouch(car(tailA) car(tailB))
      location=xkC2Pair(car(tailA) car(tailB))
      when(location hits=cons(location hits))))
    tailB=cdr(tailB))
   tailA=cdr(tailA))
  return(hits)))

procedure(xkC2AngleNet(paths)
 prog((hits previous location)
  foreach(segments paths
   previous=nil
   foreach(segment segments
    when(xkC2Pulse(nil) return(nil))
    when(xkC2__lgs_line_length(segment)>xkC2_lgs_degree_length
     when(previous
      location=xkC2__lgs_Is90degree(previous segment)
      when(location hits=cons(location hits)))
     previous=segment)))
  return(hits)))

procedure(xkC2Paths(net)
 let((paths)
  foreach(branch net->branches
   foreach(child branch->children
    when(child->objType=="path" && child->segments paths=cons(child->segments paths))))
  paths))

procedure(xkC2Run(names mode)
 prog((table net paths hits resultNames resultPoints)
  xkC2Skipped=nil xkC2Done=0 xkC2Total=length(names) xkC2Work=0
  xkC2Cancelled=nil xkC2Current="初始化"
  table=makeTable('xkC2NetLookup nil)
  foreach(item axlDBGetDesign()->nets when(item->name table[item->name]=item))
  foreach(name names
   xkC2Current=name
   when(xkC2Pulse(t) return(list(resultNames resultPoints)))
   net=table[name]
   paths=if(net then xkC2Paths(net) else nil)
   hits=nil
   if(mode==0 && length(paths)>200 then
    xkC2Skipped=cons(name xkC2Skipped)
   else
    hits=if(mode==0 then xkC2LoopNet(paths) else xkC2AngleNet(paths)))
   when(xkC2Cancelled return(list(resultNames resultPoints)))
   foreach(location hits resultNames=cons(name resultNames) resultPoints=cons(location resultPoints))
   xkC2Done=xkC2Done+1)
  return(list(resultNames resultPoints))))

procedure(xkC2Report()
 let((port)
  port=outfile("xiaokai_C2_check.log")
  when(port
   fprintf(port "C2：%s\n状态：%s\n已处理网络 %d / %d\n结果 %d 项\n"
    if(xkC2_lgs_command==0 then "环路候选检查" else "直角/锐角检查")
    if(xkC2Cancelled then "用户中止，结果不完整" else "检查结束")
    xkC2Done xkC2Total length(xkC2_lgs_errlist))
   when(xkC2Skipped
    fprintf(port "\n沿用原版超过 200 条路径的网络跳过规则，以下网络未检查：\n")
    foreach(name xkC2Skipped fprintf(port "%s\n" name)))
   close(port))))

procedure(xkC2__lgs_ac_check()
 prog((result enabled buttons meterFile port definition)
  when(xkC2Busy return(nil))
  unless(xkC2_lgs_netlist axlUIWPrint(xkC2_lgs_ac_form "没有匹配的网络。") return(nil))
  xkC2Busy=t
  enabled=axlGetFindFilter(nil) buttons=axlGetFindFilter(t)
  meterFile="./xiaokai_C2_progress.form"
  definition=strcat(
   "FILE_TYPE=FORM_DEFN VERSION=2\t\nFORM\t\nFIXED\t\nPORT 86 21\t\nHEADER \"C2：检查进度\"\t\nTILE\t\n"
   "TEXT\t\nTLOC 2 1\t\nINFO progressText 80\t\nENDTEXT\t\n"
   "FIELD bar\t\nFLOC 2 5\t\nPROGRESS 80 4\t\nENDFIELD\t\n"
   "TEXT\t\nTLOC 2 10\t\nINFO progressText2 80\t\nENDTEXT\t\n"
   "FIELD Cancel\t\nFLOC 2 14\t\nMENUBUTTON \"停止检查\" 22 3\t\nENDFIELD\t\nENDTILE\t\nENDFORM\t\n")
  port=outfile(meterFile)
  unless(port xkC2Busy=nil return(nil))
  fprintf(port "%s" definition) close(port)
  unless(axlMeterCreate("C2：检查进度" "准备检查" t meterFile)
   xkC2Busy=nil return(nil))
  axlCancelOn()
  axlUIWPrint(xkC2_lgs_ac_form "正在检查；进度窗口显示当前网络，可停止。")
  result=errset(xkC2Run(xkC2_lgs_netlist xkC2_lgs_command) t)
  axlCancelOff()
  axlMeterDestroy()
  when(isFile(meterFile) deleteFile(meterFile))
  axlClearSelSet()
  axlSetFindFilter(?enabled enabled ?onButtons buttons)
  xkC2Busy=nil
  if(result then
   xkC2_lgs_errlist=caar(result) xkC2_lgs_errlistxy=cadar(result)
   xkC2_lgs_list_mode="err"
   axlFormSetField(xkC2_lgs_ac_form "lgs_net_err" "error")
   axlFormListDeleteAll(xkC2_lgs_ac_form "Err_List")
   when(xkC2_lgs_errlist axlFormSetField(xkC2_lgs_ac_form "Err_List" xkC2_lgs_errlist))
   xkC2Report()
   axlUIWPrint(xkC2_lgs_ac_form "%s：%d/%d 网络，%d 项；跳过 %d 网。"
    if(xkC2Cancelled then "已停止（结果不完整）" else "检查结束")
    xkC2Done xkC2Total length(xkC2_lgs_errlist) length(xkC2Skipped))
  else axlUIWPrint(xkC2_lgs_ac_form "检查出错，已退出；请查看命令窗口。"))
  return(result)))
