# SPDX-License-Identifier: GPL-3.0-only
source [file join [file dirname [info script]] .. .. autoload drctoolMenu.tcl]
package require Tk
wm withdraw .
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
set clickTime 1000
proc doubleClick {tree row column} {
    $tree see $row
    update
    lassign [$tree bbox $row $column] x y width height
    assert {$height > 0}
    incr x [expr {$column eq "#0" ? 45 : 20}]
    incr y [expr {$height / 2}]
    incr ::clickTime 1000
    foreach {event offset} {<ButtonPress-1> 0 <ButtonRelease-1> 30 <ButtonPress-1> 60 <ButtonRelease-1> 90} {
        event generate $tree $event -x $x -y $y -time [expr {$::clickTime + $offset}]
    }
    update
}
try {
    ::xiaokai::drc::show
    set row [::xiaokai::drc::row unconnected_pin {schematic FULLADD message {WARNING(ORCAP-1831): Unconnected pin U1A,I0}}]
    dict set row hierarchy_path /
    dict set row sheet_name FULLADD
    dict set row _schematic FULLADD
    dict set row _targets [list [dict create refdes U1A pin_number I0 _part_id 1 _pin_id 10]]
    set second [dict replace $row pin_info I1 message {WARNING(ORCAP-1831): Unconnected pin U1A,I1}]
    dict set second _targets [list [dict create refdes U1A pin_number I1 _part_id 1 _pin_id 11]]
    set ::xiaokai::drc::result [dict create rows [list $row $second]]
    ::xiaokai::drc::render
    set t .xiaokaiDrc.list.tree
    set parents [$t children {}]
    assert {[llength $parents] == 1}
    set parent [lindex $parents 0]
    assert {[llength [$t children $parent]] == 2}
    $t selection set $parent
    ::xiaokai::drc::uiSelect
    assert {![winfo exists .xiaokaiDrc.bottom.jump]}
    set child [lindex [$t children $parent] 1]
    $t selection set $child
    ::xiaokai::drc::uiSelect
    rename ::xiaokai::drc::locate ::xiaokai::drc::savedLocate
    set ::locateCalls 0
    proc ::xiaokai::drc::locate {row result} {incr ::locateCalls; set ::located $row}
    doubleClick $t $parent #0
    assert {[$t item $parent -open] && $::locateCalls == 0}
    # Double-click text and location cells, with another row initially selected.
    doubleClick $t [lindex [$t children $parent] 0] #0
    assert {$::locateCalls == 1 && [dict get $::located pin_info] eq "I0"}
    doubleClick $t $child location
    assert {$::locateCalls == 2}
    assert {[dict get $::located pin_info] eq "I1"}
    ::xiaokai::drc::uiNative
    assert {[string first ORCAP-1831 [.xiaokaiDrc.tabs.native.text get 1.0 end]] >= 0}
    set ::xiaokai::drc::query DOES_NOT_EXIST
    ::xiaokai::drc::render
    assert {[llength [$t children {}]] == 0}
    assert {[wm title .xiaokaiDrc] eq "DRC\u4e2d\u6587\u589e\u5f3a\u7248 v$::xiaokai::drc::version"}
    source [file join [file dirname [info script]] .. .. autoload xiaokaiSchematicPlugins.tcl]
    rename ::xiaokai::drc::run ::xiaokai::drc::savedRun
    set ::runCalls 0
    proc ::xiaokai::drc::run {args} {incr ::runCalls; return {rows {} counts {} violations 0 waived 0}}
    xiaokaiSchematicPluginsOpen
    .xiaokaiSchematicPlugins.results.tv selection set drctool
    assert {[xiaokaiSchematicPluginsRun]}
    update
    assert {$::runCalls == 1}
    assert {[wm state .xiaokaiSchematicPlugins] eq "iconic"}
    assert {[wm attributes .xiaokaiDrc -topmost]}
    assert {[wm state .xiaokaiDrc] eq "normal"}
    set bad [::xiaokai::drc::row netlist_error {message {ERROR(ORCAP-3): Invalid property}}]
    set ::xiaokai::drc::query ""
    set ::xiaokai::drc::result [dict create rows [list $bad]]
    ::xiaokai::drc::render
    set parent [lindex [$t children {}] 0]
    $t selection set [lindex [$t children $parent] 0]
    ::xiaokai::drc::uiSelect
    $t item $parent -open 1
    doubleClick $t [lindex [$t children $parent] 0] location
    assert {$::locateCalls == 2}
    set leaf [lindex [$t children $parent] 0]
    assert {[string first "\u65e0\u5b9a\u4f4d\u4fe1\u606f" [$t set $leaf location]] >= 0}
    assert {[string first "\u65e0\u5b9a\u4f4d\u4fe1\u606f" [.xiaokaiDrc.bottom.text get 1.0 end]] >= 0}
    # An edit latches stale state, blocks both navigation and export, and only
    # a completed new check clears it. Switching projects alone is temporary.
    rename ::xiaokai::drc::resultState ::xiaokai::drc::savedResultState
    proc ::xiaokai::drc::resultState {r} {return $::freshState}
    set ::xiaokai::drc::completeStatus COMPLETE
    set freshState other
    assert {![::xiaokai::drc::refreshFreshness $::xiaokai::drc::result]}
    assert {!$::xiaokai::drc::stale}
    set freshState current
    assert {[::xiaokai::drc::refreshFreshness $::xiaokai::drc::result]}
    assert {$::xiaokai::drc::status eq "COMPLETE"}
    set freshState stale
    ::xiaokai::drc::pollFreshness
    assert {$::xiaokai::drc::stale && [.xiaokaiDrc.bar.export cget -state] eq "disabled"}
    assert {[string first "\u7ed3\u679c\u5f85\u66f4\u65b0" $::xiaokai::drc::status] >= 0}
    ::xiaokai::drc::uiLocateRow $row $::xiaokai::drc::result
    ::xiaokai::drc::uiExport
    assert {$::locateCalls == 2}
    set freshState current
    assert {![::xiaokai::drc::refreshFreshness $::xiaokai::drc::result]}
    ::xiaokai::drc::uiCheck
    assert {!$::xiaokai::drc::stale && [.xiaokaiDrc.bar.export cget -state] eq "normal"}
    puts "PASS: no-location label, project switch recovery, edit invalidation, navigation/export blocked, recheck reset"
    puts "PASS: real mouse double-click on row text/location, group expansion, exact clicked row, no extra jump button"
    puts "PASS: direct launcher auto-check, collection minimized, DRC foreground, untargeted netlist errors cannot misnavigate"
    set ::xiaokai::drc::query ""
    set ::xiaokai::drc::result {rows {}}
    ::xiaokai::drc::render
    assert {[llength [$t children {}]] == 0}
    puts "PASS: Tk grouping, expand rows, selection, location dispatch, native details, search, empty results"
} on error {msg opts} {
    puts stderr [dict get $opts -errorinfo]
    exit 1
}
exit 0
