source -encoding utf-8 [file join [file dirname [info script]] core.tcl]
source -encoding utf-8 [file join [file dirname [info script]] presentation.tcl]
source -encoding utf-8 [file join [file dirname [info script]] review.tcl]
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
set target {refdes U12 _part_id 10 _pin_id 11 pin_number 3}
set row [dict create rule_id unconnected_pin hierarchy_path / _schematic ROOT sheet_name PAGE \
    message {WARNING(ORCAP-1831): Unconnected pin U12,IN} _targets [list $target] _pin_specific 1]
set checked [dict create rows [list $row] source D:/fixture.dsn design design workdir unused \
    review_contexts {{path / schematic ROOT}}]
set ns ::xiaokai::drc
assert {[dict get [${ns}::reviewCandidate $row $checked] part_id] == 10}
assert {[catch {${ns}::reviewCandidate $row [dict replace $checked review_contexts {{path /A schematic ROOT} {path /B schematic ROOT}}]}]}
assert {[catch {${ns}::reviewCandidate $row [dict remove $checked review_contexts]}]}
assert {[catch {${ns}::reviewCandidate [dict replace $row _targets {}] $checked}]}
assert {[catch {${ns}::reviewCandidate [dict replace $row _targets [list $target [dict replace $target _part_id 20]]] $checked}]}
assert {[catch {${ns}::reviewCandidate [dict replace $row _targets [list $target [dict replace $target _pin_id 12]]] $checked}]}
assert {[catch {${ns}::reviewCandidate [dict replace $row rule_id netlist_error] $checked}]}
assert {[${ns}::reviewKeys [list $row]] ne [${ns}::reviewKeys [list [dict replace $row hierarchy_path /B]]]}
assert {[${ns}::reviewKeys [list $row]] ne [${ns}::reviewKeys [list [dict replace $row message other]]]}
proc ${ns}::resultState {r} {return $::state}
proc ${ns}::reviewPlacement {entry r {offset 0} {reserved {}}} {return [dict merge $entry [dict create x 100 y [expr {100+$offset*25}]]]}
proc ${ns}::reviewBackup {r} {incr ::backups; return backup.dsn}
rename ${ns}::reviewOwned ${ns}::nativeReviewOwned
proc ${ns}::reviewOwned {d} {return {}}
proc ${ns}::reviewCreate {entry checked token} {incr ::writes; if {$::failWrite} {error CREATE_FAILED}}
proc ${ns}::reviewConnectivity {design} {return $::graph}
proc ${ns}::run {args} {if {$::failCheck} {error CHECK_FAILED}; if {$::graphAfter ne ""} {set ::graph $::graphAfter}; return $::verified}
proc ${ns}::activeDesign {} {return design}
proc ${ns}::cstring {args} {return $::source}
proc ${ns}::saveCurrentDesign {d} {incr ::saves}
rename ${ns}::reviewRemove ${ns}::nativeReviewRemove
proc ${ns}::reviewRemove {d {token ""}} {incr ::removals; return {removed 1 preserved 0}}
set source D:/fixture.dsn; set state current; set failWrite 0; set failCheck 0
set graph unchangedGraph; set graphAfter ""
set writes 0; set backups 0; set removals 0; set saves 0; set verified $checked
set entry [dict merge [${ns}::reviewCandidate $row $checked] {x 100 y 100 text {已确认：U12 的 3 脚漏接} confirmed 1}]
set state stale
assert {[catch {${ns}::reviewApply [list $entry] $checked}] && $writes == 0 && $backups == 0}
set state other
assert {[catch {${ns}::reviewApply [list $entry] $checked}] && $writes == 0}
set state current
foreach invalid [list [dict remove $entry confirmed] [dict replace $entry x 101] [dict replace $entry text ""]] {
    assert {[catch {${ns}::reviewApply [list $invalid] $checked}] && $writes == 0}
}
assert {[catch {${ns}::reviewApply [list $entry $entry] $checked}] && $writes == 0}
set applied [${ns}::reviewApply [list $entry] $checked]
assert {$writes == 1 && $backups == 1 && [dict get $applied count] == 1 && $removals == 0}
set verified [dict replace $checked rows {}]
assert {[catch {${ns}::reviewApply [list $entry] $checked}] && $removals == 1 && $saves == 1}
set verified $checked; set failCheck 1
assert {[catch {${ns}::reviewApply [list $entry] $checked}] && $removals == 2}
set failCheck 0; set failWrite 1
assert {[catch {${ns}::reviewApply [list $entry] $checked}] && $removals == 3}
set source D:/different.dsn
assert {[catch {${ns}::reviewApply [list $entry] $checked}] && $removals == 3}
set source D:/fixture.dsn; set failWrite 0; set graphAfter changedGraph
assert {[catch {${ns}::reviewApply [list $entry] $checked}] && $removals == 4}
set graphAfter ""; set graph unchangedGraph; set verified [dict replace $checked source D:/other.dsn]
assert {[catch {${ns}::reviewApply [list $entry] $checked}] && $removals == 5}
assert {!$::xiaokai::drc::reviewMutating}

# Removing notes respects content edits, token isolation and iterator lifetime.
rename ${ns}::reviewRemove {}; rename ${ns}::nativeReviewRemove ${ns}::reviewRemove
rename ${ns}::reviewOwned {}
proc ${ns}::reviewOwned {d} {return $::owned}
set owned [list [dict create page page inst a unchanged 1 metadata {token A}] \
    [dict create page page inst b unchanged 0 metadata {token A}] \
    [dict create page page inst c unchanged 1 metadata {token B}]]
set deleted {}
proc page {method args} {if {$method eq "DeleteCommentGraphic"} {lappend ::deleted [lindex $args 0]}; return ok}
proc ok {method} {if {$method eq "OK"} {return 1}}
assert {[${ns}::reviewRemove design A] eq {removed 1 preserved 1} && $deleted eq {a}}
set deleted {}
assert {[${ns}::reviewRemove design] eq {removed 2 preserved 1} && $deleted eq {a c}}
puts "PASS: unique targets, reused instances, unsupported rules, stale preview, explicit confirmation, exact placement, drift rollback, failure rollback, project isolation, edited Text preserved"
