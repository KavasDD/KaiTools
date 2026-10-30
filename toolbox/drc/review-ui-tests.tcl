source [file join [file dirname [info script]] .. .. autoload drctoolMenu.tcl]
package require Tk; wm withdraw .
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
set ns ::xiaokai::drc
rename ${ns}::resultState ${ns}::nativeResultState
proc ${ns}::resultState {r} {return $::state}
rename ${ns}::reviewPlacement ${ns}::nativeReviewPlacement
proc ${ns}::reviewPlacement {entry r {offset 0} {reserved {}}} {
    if {$::noSpace} {error NO_SPACE}
    return [dict merge $entry [dict create x 100 y [expr {100+[llength $reserved]*20}]]]
}
rename ${ns}::locate ${ns}::nativeLocate
proc ${ns}::locate {row checked} {incr ::located}
rename ${ns}::reviewApply ${ns}::nativeReviewApply
proc ${ns}::reviewApply {entries checked} {
    incr ::applies; set ::placed $entries
    if {$::failApply} {error WRITE_FAILED}
    return [dict create result $checked count [llength $entries]]
}
rename ${ns}::reviewRemove ${ns}::nativeReviewRemove
proc ${ns}::reviewRemove {args} {incr ::removals; return [dict create removed $::ownedCount preserved 0]}
rename ${ns}::activeDesign ${ns}::nativeActiveDesign
proc ${ns}::activeDesign {} {return design}
rename ${ns}::cstring ${ns}::nativeCString
proc ${ns}::cstring {args} {return $::designPath}
rename ${ns}::run ${ns}::nativeRun
proc ${ns}::run {args} {incr ::checks; set ::state current; return $::checked}
proc tk_messageBox {args} {error UNEXPECTED_POPUP}
set row [dict create rule_id unconnected_pin hierarchy_path / _schematic ROOT sheet_name PAGE refdes U12 \
    message {WARNING(ORCAP-1831): Unconnected pin U12,IN} \
    _targets {{refdes U12 _part_id 10 _pin_id 11 pin_number 3}} _pin_specific 1]
set other [dict replace $row rule_id single_node_nets message {WARNING(ORCAP-1600): Net has fewer than two connections N} \
    _targets {{refdes U12 _part_id 10 _pin_id 12 pin_number 4}}]
set reused [dict replace $row hierarchy_path /A _schematic SHARED]
set checked [dict create design design source D:/checked.dsn rows [list $row $other $reused] \
    review_contexts {{path / schematic ROOT} {path /A schematic SHARED} {path /B schematic SHARED}}]
set ::xiaokai::drc::result $checked
set state current; set located 0; set applies 0; set removals 0; set checks 0
set noSpace 0; set failApply 0; set ownedCount 0; set designPath D:/checked.dsn
try {
    ${ns}::show; ${ns}::reviewShow $other
    wm geometry .xiaokaiDrc 640x430; update
    assert {[winfo x .xiaokaiDrc.bar.text] >= 0 && [winfo x .xiaokaiDrc.bar.text]+[winfo width .xiaokaiDrc.bar.text] <= [winfo width .xiaokaiDrc.bar]}
    assert {[.xiaokaiDrc.bar.text cget -text] eq "一键放置 Text"}
    assert {[.xiaokaiDrc.tabs.review.tree selection] eq "r2"}
    assert {![winfo exists .xiaokaiDrc.tabs.review.buttons] && ![winfo exists .xiaokaiDrc.tabs.review.edit]}
    assert {$::xiaokai::drc::reviewNote eq "单点连接"}
    assert {[string first ORCAP-1600 [.xiaokaiDrc.tabs.review.evidence get 1.0 end]] >= 0}
    ${ns}::reviewLocate; assert {$located == 1}
    .xiaokaiDrc.bar.text invoke
    assert {$applies == 1 && [llength $placed] == 2 && $::xiaokai::drc::reviewVisible}
    assert {[.xiaokaiDrc.bar.text cget -text] eq "关闭 Text"}
    assert {[dict get [lindex $placed 0] text] eq "核对漏接"}
    assert {[dict get [lindex $placed 1] text] eq "单点连接"}
    assert {[dict get [lindex $placed 1] y] == 120}
    assert {[string first {1 项仅保留在列表} $::xiaokai::drc::status] >= 0}
    assert {![winfo exists .xiaokaiDrc.tabs.review.tree]}
    set ownedCount 2; set before $removals
    .xiaokaiDrc.bar.text invoke
    assert {!$::xiaokai::drc::reviewVisible && $removals == $before+1 && $checks == 1}
    set ownedCount 0; set state stale; set ::xiaokai::drc::stale 1
    .xiaokaiDrc.bar.text invoke
    assert {$checks == 2 && $applies == 2 && $::xiaokai::drc::reviewVisible}
    set designPath D:/other.dsn; set before $removals
    .xiaokaiDrc.bar.text invoke
    assert {$removals == $before && $::xiaokai::drc::reviewVisible}
    set designPath D:/checked.dsn; set ::xiaokai::drc::stale 0
    .xiaokaiDrc.bar.text invoke
    set noSpace 1; set before $applies
    .xiaokaiDrc.bar.text invoke
    assert {$applies == $before && !$::xiaokai::drc::reviewVisible}
    assert {[string first NO_SPACE [.xiaokaiDrc.bottom.text get 1.0 end]] >= 0}
    set noSpace 0; set failApply 1
    .xiaokaiDrc.bar.text invoke
    assert {!$::xiaokai::drc::reviewVisible && !$::xiaokai::drc::reviewWorking}
    assert {[string first WRITE_FAILED $::xiaokai::drc::status] >= 0}
    set failApply 0
    set ::xiaokai::drc::reviewPreview $checked
    set ::xiaokai::drc::reviewItems [dict create verified [dict create row $row ai {verdict error suggested_text 输入悬空}] \
        allowed [dict create row $other ai {verdict allowed suggested_text 允许悬空}]]
    set verifiedPlan [${ns}::reviewPlan $checked]
    assert {[llength [dict get $verifiedPlan entries]] == 1}
    assert {[dict get [lindex [dict get $verifiedPlan entries] 0] text] eq "输入悬空"}
    set ::xiaokai::drc::reviewPreview [dict replace $checked source D:/another.dsn]
    set freshPlan [${ns}::reviewPlan $checked]
    assert {[llength [dict get $freshPlan entries]] == 2}
    assert {[dict get [lindex [dict get $freshPlan entries] 0] text] eq "核对漏接"}
    puts "PASS: actual one-click switch, concise notes, fresh check, batch spacing, reused definition skipped, off/recheck, project isolation, failures without popups"
} on error {msg opts} {puts stderr [dict get $opts -errorinfo]; exit 1}
exit 0
