source [file join [file dirname [info script]] .. .. autoload drctoolMenu.tcl]
package require Tk; wm withdraw .
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
set ns ::xiaokai::drc
set a {hierarchy_path / schematic ROOT sheet_name P refdes CN10 pin_number 29 pin_name IO net_name SAME flat_net native-A is_primitive 1 _part_id 10 _pin_id 11 _pin_point {100 200}}
set b [dict replace $a hierarchy_path /child schematic CHILD sheet_name P2 refdes U2 _part_id 20 _pin_id 21 pin_number 3 _pin_point {700 400}]
set wrong [dict replace $a hierarchy_path /other refdes U3 flat_net native-B _part_id 30 _pin_id 31]
set related [dict replace $a pin_number 30 flat_net native-B _pin_id 12]
set block [dict replace $a refdes BLOCK is_primitive 0 _part_id 40]
set unresolved [dict replace $a flat_net {} pin_number 31 _pin_id 13]
set fixture [dict create pins [list $a $b $b $wrong $related $block $unresolved]]
set row [dict create rule_id single_node_nets hierarchy_path / _schematic ROOT sheet_name P refdes CN10 _targets [list $a] message {Net SAME has fewer than two connections}]
set facts [${ns}::connectionFacts $row $fixture]
assert {[llength [dict get $facts networks]] == 1}
set endpoints [dict get [lindex [dict get $facts networks] 0] endpoints]
assert {[llength $endpoints] == 2 && [dict get [lindex $endpoints 1] hierarchy_path] eq "/child"}
set facts2 [${ns}::connectionFacts [dict replace $row _targets [list $a $wrong]] $fixture]
assert {[llength [dict get $facts2 networks]] == 2}
set facts3 [${ns}::connectionFacts [dict replace $row _targets [list $unresolved]] $fixture]
assert {![llength [dict get $facts3 networks]] && [llength [dict get $facts3 unresolved]] == 1}
rename ${ns}::resultState ${ns}::nativeResultState
proc ${ns}::resultState {checked} {return $::state}
rename ${ns}::snapshot ${ns}::nativeSnapshot
proc ${ns}::snapshot {design} {incr ::reads; return $::fixture}
rename ${ns}::locate ${ns}::nativeLocate
proc ${ns}::locate {row checked} {lappend ::located [list $row $checked]}
set state current; set reads 0; set located {}
set checked [dict create design mock rows [list $row] review_contexts {{path / schematic ROOT}}]
set ::xiaokai::drc::result $checked
${ns}::show; ${ns}::reviewShow
wm geometry .xiaokaiDrc 900x590; update
foreach region {.xiaokaiDrc.tabs.review.tree .xiaokaiDrc.tabs.review.connections.tree .xiaokaiDrc.tabs.review.evidence} {
    assert {[winfo ismapped $region] && [winfo height $region] > 25}
}
set t .xiaokaiDrc.tabs.review.connections.tree
assert {[llength [$t children {}]] == 2 && $reads == 1}
${ns}::reviewSelect; assert {$reads == 1}
assert {[$t set c2 refdes] eq "U2"}
assert {[string first /child [$t set c2 position]] >= 0}
# Exercise the real Tk row lookup; previous selection is deliberately another pin.
$t selection set c1
$t see c2; update
lassign [$t bbox c2 refdes] x y width height
${ns}::connectionClick [expr {$x+3}] [expr {$y+$height/2}]; update
assert {[llength $located] == 1}
set jump [lindex [lindex $located 0] 0]
assert {[dict get $jump hierarchy_path] eq "/child" && [dict get $jump _schematic] eq "CHILD"}
assert {[dict get $jump _pin_specific] && [dict get $jump _focus_point] eq {700 400}}
assert {[dict get [lindex [dict get $jump _targets] 0] _pin_id] == 21}
set state stale
${ns}::connectionLocate $b $checked
assert {[llength $located] == 1 && [string first 变化 $::xiaokai::drc::connectionStatus] >= 0}
${ns}::connectionRender $row $checked
assert {![llength [$t children {}]] && ![dict size $::xiaokai::drc::connectionRows]}
set state current
dict set ::xiaokai::drc::reviewItems r1 ai {verdict uncertain baseline 1 reason {不应显示的重复长篇解释} evidence F1.DRC}
${ns}::reviewReflow; ${ns}::reviewSelect
assert {[.xiaokaiDrc.tabs.review.tree parent r1] eq "noEvidence"}
assert {[string first 未获得可判错的新依据 [.xiaokaiDrc.tabs.review.evidence get 1.0 end]] >= 0}
assert {[string first 重复长篇 [.xiaokaiDrc.tabs.review.evidence get 1.0 end]] < 0}
set groupTree .xiaokaiDrc.tabs.review.tree
$groupTree see noEvidence; update
lassign [$groupTree bbox noEvidence position] gx gy gw gh
${ns}::reviewDouble [expr {$gx+3}] [expr {$gy+$gh/2}]
assert {[$groupTree item noEvidence -open]}
assert {[llength $located] == 1}
# Repeated analysis can promote a previously grouped item without losing it.
dict set ::xiaokai::drc::reviewItems r1 ai {verdict error baseline 0 reason 输入悬空 suggested_text 输入悬空 sources {PDF 第11页}}
${ns}::reviewReflow
assert {![.xiaokaiDrc.tabs.review.tree exists noEvidence] && [.xiaokaiDrc.tabs.review.tree exists r1]}
assert {[.xiaokaiDrc.tabs.review.tree parent r1] eq ""}
set state other
assert {[catch {${ns}::connectionModel $checked}]}
assert {$reads == 1}
puts "PASS: cross-hierarchy native net endpoints, same-name isolation, unresolved targets, duplicate/block exclusion, cache, clicked-pin location, stale/project guard, grouped baseline and promotion"
exit 0
