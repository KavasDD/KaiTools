source -encoding utf-8 [file join [file dirname [info script]] core.tcl]
source -encoding utf-8 [file join [file dirname [info script]] placement.tcl]
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
set ns ::xiaokai::drc
assert {[${ns}::reviewTextSize \u5355\u70b9\u8fde\u63a5] eq {36 12}}
proc ${ns}::reviewPage {args} {return page}
proc ${ns}::reviewFaultPoint {args} {return $::fault}
set fault {500 500}
set candidate [dict create part_id 1 row {_schematic ROOT sheet_name P} text "\u6838\u5bf9\u6f0f\u63a5"]
set a [${ns}::reviewPlacement $candidate {design design}]
assert {[dict get $a x] == 500 && [dict get $a y] == 500}
assert {[dict get $a text_rect] eq {500 500 536 512}}
# Batch reservations and page-edge points never trigger avoidance or offsets.
set b [${ns}::reviewPlacement $candidate {design design} 5 [list $a]]
assert {[dict get $a text_rect] eq [dict get $b text_rect]}
set fault {0 0}
set c [${ns}::reviewPlacement $candidate {design design}]
assert {[dict get $c x] == 0 && [dict get $c y] == 0}
# Always reread the fault; stale report coordinates do not control placement.
set fault {710 420}
dict set candidate row _focus_point {500 500}
set d [${ns}::reviewPlacement $candidate {design design}]
assert {[dict get $d fault_point] eq {710 420}}
puts "PASS: exact current fault coordinate, unchanged compact text size, no reservation offset, page-edge anchoring"
