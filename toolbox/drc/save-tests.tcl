# SPDX-License-Identifier: GPL-3.0-only
source -encoding utf-8 [file join [file dirname [info script]] core.tcl]
source -encoding utf-8 [file join [file dirname [info script]] capture.tcl]
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
proc DboSession {args} {assert {$args eq {-this session}}}
proc session {method design} {
    assert {$method in {SaveDesign MarkAllLibForSave} && $design eq "checkedDesign"}
    if {$method eq "MarkAllLibForSave"} {return markStatus}
    incr ::saves
    if {$::mode eq "throw"} {error "Native write failed"}
    if {$::mode eq "ok"} {set ::dirty 0}
    return saveStatus
}
proc markStatus {method} {if {$method eq "OK"} {return 1}; if {$method eq "-delete"} {incr ::marksReleased; return}; error $method}
proc saveStatus {method} {
    if {$method eq "OK"} {return [expr {$::mode ne "fail"}]}
    if {$method eq "-delete"} {incr ::released; return}
    error $method
}
proc DboState {} {return state}
proc state {method} {if {$method eq "-delete"} {incr ::statesReleased; return}; error $method}
proc checkedDesign {method state} {assert {$method eq "IsModified"}; return $::dirty}
set DboSession_s_pDboSession session
set saves 0; set released 0; set statesReleased 0; set marksReleased 0
foreach mode {ok fail dirty throw} {
    set dirty 1
    set rc [catch {::xiaokai::drc::saveCurrentDesign checkedDesign} message]
    assert {$rc == ($mode ne "ok")}
    if {$mode eq "ok"} {assert {!$dirty}}
}
assert {$saves == 4 && $released == 3 && $statesReleased == 2}
assert {$marksReleased == 4}
unset DboSession_s_pDboSession
assert {[catch {::xiaokai::drc::saveCurrentDesign checkedDesign}]}
assert {$saves == 4}
puts "PASS: native save targets checked design only, dirty state verified, write/dirty/session failures rejected, handles released"
