; Exercise the real Allegro interpreter and companion pipe on a board copy.
procedure(xkAppearanceAssert(value message)
  if(value then
    fprintf(xkAppearanceReport "PASS: %s\n" message)
  else
    fprintf(xkAppearanceReport "FAIL: %s\n" message)
    xkAppearanceFailures = xkAppearanceFailures + 1
  )
)
xkAppearanceFailures = 0
xkAppearanceReport = outfile(xkAppearanceReportPath)
xkAllegroInstallRoot = strcat(xkAppearanceRoot "/skill")
xkAppearanceAssert(errset(load(strcat(xkAllegroInstallRoot "/quick_grids.il")) t) "load existing grids")
xkAppearanceAssert(errset(load(strcat(xkAllegroInstallRoot "/xiaokaiAllegroMenu.il")) t) "load new generated SKILL")
xkAppearanceAssert(ipcIsAliveProcess(xkToolboxHotkeyProcess) "companion process belongs to Allegro")
xkAppearanceAssert(errset(xkSkillToolbox() t) "send TOOLBOX to companion")
ipcSleep(2)
xkAppearanceAssert(ipcIsAliveProcess(xkToolboxHotkeyProcess) "companion remains alive after opening")
foreach(command '("find component" "find drc" "quick_grids" "quick_display" "conv" "hps"
    "xk_library_paths" "show_height" "xk_production_setup" "cvia" "xk_dangling_check")
  xkAppearanceAssert(xkToolboxCommandAllowed(command) command))
xkAppearanceAssert(not(xkToolboxCommandAllowed("exit")) "reject commands outside toolbox")
xkAppearanceAssert(errset(xkToolboxHandleLine("EXEC quick_grids") t) "dispatch existing grid action")
xkAppearanceAssert(errset(xkToolboxHotkeyData(nil "EXEC invalid\nEXEC ") t) "accept combined and split IPC data")
xkAppearanceAssert(errset(xkToolboxHotkeyData(nil "invalid\n") t) "complete split data without execution")
fprintf(xkAppearanceReport "FAILURES: %d\n" xkAppearanceFailures)
close(xkAppearanceReport)
