# Launched by the local mock HTTP test, never reads real provider settings.
source [file join [file dirname [info script]] .. .. autoload drctoolMenu.tcl]
package require Tk; wm withdraw .
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
set ns ::xiaokai::drc
set ::env(XIAOKAI_AI_TEST_CONFIG) [lindex $argv 1]
set ::fixtureHelper [lindex $argv 0]
rename ${ns}::aiHelper ${ns}::realAiHelper
proc ${ns}::aiHelper {} {return $::fixtureHelper}
rename ${ns}::resultState ${ns}::realResultState
proc ${ns}::resultState {r} {return current}
rename ${ns}::snapshot ${ns}::realSnapshot
proc ${ns}::snapshot {d} {return $::fixture}
set pin {hierarchy_path / schematic ROOT sheet_name P refdes U1 pin_number 3 pin_name EN pin_type 1 net_name N local_net N flat_net native-pointer _part_id 10 _pin_id 11}
set fixture [dict create pins [list $pin]]
set row [dict create rule_id unconnected_pin hierarchy_path / _schematic ROOT sheet_name P refdes U1 \
    _targets [list $pin] _pin_specific 1 message {WARNING(ORCAP-1831): Unconnected pin U1,EN}]
set ::xiaokai::drc::result [dict create design mock rows [list $row] review_contexts {{path / schematic ROOT}}]
${ns}::show; ${ns}::reviewShow
.xiaokaiDrc.tabs.review.tree selection set r1; ${ns}::reviewSelect
${ns}::aiStart
proc checkDone {} {
    if {![dict size $::xiaokai::drc::aiJob]} {set ::done 1} else {after 100 checkDone}
}
after 100 checkDone
after 12000 {set ::done timeout}
vwait ::done
assert {$::done ne "timeout"}
if {[lindex $argv 2] eq "expect-failure"} {
    assert {![dict exists $::xiaokai::drc::reviewItems r1 ai]}
    set detail [.xiaokaiDrc.tabs.review.evidence get 1.0 end]
    assert {[string first 模型返回片段 $detail]>=0}
    assert {[string first {无法直接打开 DSN} $detail]>=0}
    assert {[string first secret-dummy-key $detail]<0 && [string first another-private-token $detail]<0}
    assert {[string first 重试后仍失败 $::xiaokai::drc::aiStatus]>=0}
    assert {[string first \n $::xiaokai::drc::aiStatus]<0}
    assert {[string first {自动重试一次} [.xiaokaiDrc.tabs.review.progressLog get 1.0 end]]>=0}
    puts "PASS: failed model response and retry shown inline; credentials hidden; no AI result applied"
    exit 0
}
assert {[dict exists $::xiaokai::drc::reviewItems r1 ai]}
assert {![dict size $::xiaokai::drc::reviewConfirmed]}
assert {[.xiaokaiDrc.tabs.review.tree set r1 state] eq "未证实"}
assert {[.xiaokaiDrc.tabs.review.tree parent r1] eq "noEvidence"}
assert {![.xiaokaiDrc.tabs.review.tree item noEvidence -open]}
assert {[string first 未获得可判错的新依据 [.xiaokaiDrc.tabs.review.evidence get 1.0 end]] >= 0}
.xiaokaiDrc.tabs.review.tree item noEvidence -open 1
.xiaokaiDrc.tabs.review.tree selection set r1
${ns}::reviewSelect
set evidence [.xiaokaiDrc.tabs.review.evidence get 1.0 end]
assert {[string first F1.DRC $evidence] >= 0}
assert {[string first native-pointer $evidence] == -1 && [string first U1 $evidence] >= 0}
assert {$::xiaokai::drc::reviewNote eq "核对漏接"}
set log [.xiaokaiDrc.tabs.review.progressLog get 1.0 end]
assert {[string first {HTTP 200} $log]>=0}
assert {[string first 证据校验完成 $log]>=0}
assert {[string first secret-dummy-key $log]<0}
assert {![llength [.xiaokaiDrc.tabs.review.progress state]]}
puts "PASS: actual Tk -> asynchronous helper -> local HTTP -> validated evidence and suggestion, no auto-confirmation"
exit 0
