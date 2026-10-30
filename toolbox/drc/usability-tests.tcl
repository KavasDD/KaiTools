# SPDX-License-Identifier: GPL-3.0-only
source -encoding utf-8 [file join [file dirname [info script]] core.tcl]
source -encoding utf-8 [file join [file dirname [info script]] presentation.tcl]
source -encoding utf-8 [file join [file dirname [info script]] capture.tcl]
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
set ns ::xiaokai::drc
set target {hierarchy_path /A sheet_name PAGE refdes U12 pin_number 3 pin_name IN _part_id 10 _pin_id 11 _pin_point {350 190}}
set a [${ns}::row unconnected_pin {message {WARNING(ORCAP-1831): Unconnected pin U12,IN (3.50, 1.90)}}]
set a [dict merge $a [dict create hierarchy_path /A sheet_name PAGE _schematic CHILD _targets [list $target] _pin_specific 1 _focus_point {350 190}]]
assert {[dict get [${ns}::explain $a] summary] eq "U12 \u7684 3 \u811a\u672a\u8fde\u63a5"}
set b [dict replace $a rule_id netlist_error rule_name Netlist message {ERROR(ORCAP-3): Invalid pin U12,IN (3.50, 1.90)}]
set linked [${ns}::relatedRows [list $b $a]]
assert {[llength $linked] == 1}
set merged [lindex $linked 0]
assert {[llength [dict get $merged _related]] == 2}
assert {[string first ORCAP-3 [dict get $merged message]] >= 0 && [string first ORCAP-1831 [dict get $merged message]] >= 0}
assert {[dict get $merged rule_id] eq "unconnected_pin"}
assert {[dict size $::xiaokai::drc::rules] == 11}
assert {[llength [${ns}::relatedRows [list $a [dict replace $b hierarchy_path /B]]]] == 2}
assert {[llength [${ns}::relatedRows [list $a [dict replace $b message {ERROR(ORCAP-3): (3.60, 1.90)}]]]] == 2}
assert {[llength [${ns}::relatedRows [list $a [dict replace $b refdes U13]]]] == 2}
assert {[llength [${ns}::relatedRows [list $a $a]]] == 2}
assert {![${ns}::canLocate [dict replace $a _schematic ""]]}
assert {![${ns}::canLocate [dict replace $a _focus_point "" _targets {} message {ERROR(ORCAP-3): no object}]]}
assert {[${ns}::canLocate $a]}

# Navigation highlights the exact pin and uses its connection-end coordinates.
rename ${ns}::resultState ${ns}::realResultState
rename ${ns}::activeDesign ${ns}::realActiveDesign
rename ${ns}::cstring ${ns}::realCString
rename ${ns}::focusDesign ${ns}::realFocusDesign
proc ${ns}::resultState {result} {return $::state}
proc ${ns}::activeDesign {} {return design}
proc ${ns}::cstring {args} {return D:/live.dsn}
proc ${ns}::focusDesign {args} {return design}
proc OPage {args} {set ::opened $args}
proc UnSelectAll {} {set ::selected {}}
proc SelectObjectById {id} {lappend ::selected $id}
proc GetActivePage {} {return page}
proc page {method args} {if {$method eq "GetPhysicalGranularity"} {return $::pageScale}; error $method}
proc ZoomArea {args} {set ::area $args}
set state current; set pageScale 100
${ns}::locate $a {source D:/live.dsn}
assert {$selected eq "11" && $opened eq {CHILD PAGE A}}
assert {$area eq {3.05 1.45 3.95 2.35}}
# The same physical position under a different document scale must centre at
# the same user coordinate, rather than clamping the viewport to the edge.
set pageScale 1000
${ns}::locate [dict replace $a _focus_point {3500 1900}] {source D:/live.dsn}
assert {$area eq {3.05 1.45 3.95 2.35}}
# Coordinate-only native diagnostics take the same conversion path; wire
# lookup still receives document coordinates.
rename ${ns}::selectWireAt ${ns}::realSelectWireAt
proc ${ns}::selectWireAt {page x y tolerance} {set ::wirePoint [list $x $y]}
${ns}::locate [dict replace $a _focus_point {} _targets {}] {source D:/live.dsn}
assert {$wirePoint eq {3500 1900} && $area eq {3.2 1.6 3.8 2.2}}
foreach pageScale {0 -1 Inf NaN invalid} {
    set area unchanged
    assert {[catch {${ns}::zoomDocumentPoint page 350 190 45}] && $area eq "unchanged"}
}
set pageScale 100
set state stale; set opened {}
assert {[catch {${ns}::locate $a {source D:/live.dsn}}] && $opened eq {}}
rename ${ns}::resultState {}
rename ${ns}::realResultState ${ns}::resultState
rename ${ns}::designRevision ${ns}::realDesignRevision
proc ${ns}::designRevision {design} {return $::revision}
rename ${ns}::cstring {}
proc ${ns}::cstring {args} {return $::designPath}
rename ${ns}::activeDesign {}
proc ${ns}::activeDesign {} {return $::designHandle}
set dir [file join [file dirname [info script]] test-output freshness-[pid]]
file mkdir $dir
set designPath [file normalize [file join $dir test.dsn]]
set f [open $designPath w]; puts $f baseline; close $f
set designHandle design; set revision {page1 4 3}
set checked [dict create source $designPath source_time [file mtime $designPath] source_size [file size $designPath] design design revision $revision]
assert {[${ns}::resultState $checked] eq "current"}
set revision {page1 5 4}
assert {[${ns}::resultState $checked] eq "stale"}
set revision {page1 4 3}; set designHandle reopened
assert {[${ns}::resultState $checked] eq "stale"}
set designHandle design; set designPath [file join $dir other.dsn]
assert {[${ns}::resultState $checked] eq "other"}
set designPath [dict get $checked source]
set f [open $designPath a]; puts $f saved-edit; close $f
assert {[${ns}::resultState $checked] eq "stale"}
file delete $designPath
assert {[${ns}::resultState $checked] eq "stale"}
puts "PASS: unchanged, unsaved edits, reopened design, project switching, saved edits and moved source"
puts "PASS: object-specific Chinese, instance/point isolation, document-to-user zoom across scales, report-only wire coordinates, invalid scale blocked, stale navigation blocked"
