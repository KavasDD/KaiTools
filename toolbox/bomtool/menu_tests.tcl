# SPDX-License-Identifier: GPL-3.0-only
# Start from Tcl only. Stub the Capture UI boundary to verify the unified
# callback dispatches directly to the automatic export path.
source [file join [file dirname [info script]] .. .. autoload bomtoolMenu.tcl]
proc assert {expression} {
    if {![uplevel 1 [list expr $expression]]} { error "Assertion failed: $expression" }
}

rename package realPackage
proc package {subcommand args} {
    if {$subcommand eq "require" && [lindex $args 0] eq "Tk"} { return 8.6 }
    return [uplevel 1 [linsert $args 0 realPackage $subcommand]]
}
proc winfo {subcommand args} {
    if {$subcommand eq "exists" && [lindex $args 0] eq ".bomworkbench"} { return 0 }
    return 1
}
proc tk_chooseDirectory {args} { return $::outputParent }
proc tk_messageBox {args} { set ::resultMessage $args }

set ::outputParent [file join [file dirname [info script]] test-output direct-export-[pid]]
set ::uiRows {}
for {set n 1} {$n <= 8} {incr n} {
    set ref "ZX$n"
    lappend ::uiRows [dict create ref $ref refs [list $ref] value IC footprint SOT23]
}
proc ::bomtool::captureRows {} { return $::uiRows }
proc ::bomtool::requestCategoryOverrides {candidates} {
    set ::seenCandidates $candidates
    return [dict create ZX1 conn]
}
proc ::bomtool::exportCapture {outdir rows overrides} {
    set ::exportedTo $outdir
    set ::receivedRows $rows
    set ::receivedOverrides $overrides
    return [dict create input_references 12 groups 4 excluded 3 warnings 1 \
        workbook [file join $outdir BOM.xlsx] pending_packages 0]
}

assert {[bomtoolMenuExport context] == 1}
assert {[file isdirectory $::exportedTo]}
assert {[llength $::seenCandidates] == 1}
assert {[dict get $::receivedOverrides ZX1] eq "conn"}
assert {[string match {*BOM.xlsx*} $::resultMessage]}
assert {![winfo exists .bomworkbench]}
set previousOutput $::exportedTo
set ::outputParent ""
assert {[bomtoolMenuExport] == 0}
assert {$::exportedTo eq $previousOutput}

rename ::bomtool::exportCapture ::bomtool::realExportCapture
proc ::bomtool::exportCapture {args} { error "Injected export failure" }
proc ::bomtool::requestCategoryOverrides {candidates} { return __cancel__ }
assert {[bomtoolMenuExport] == 0}
assert {$::exportedTo eq $previousOutput}
rename ::bomtool::requestCategoryOverrides {}
proc ::bomtool::requestCategoryOverrides {candidates} { return {} }
set ::outputParent [file join [file dirname [info script]] test-output direct-export-failure-[pid]]
assert {[bomtoolMenuExport] == 0}
assert {[string match {*Injected export failure*} $::resultMessage]}
file delete -force $::outputParent

puts "PASS: unified BOM callback directly runs automatic export without opening workbench"
exit
