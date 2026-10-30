fconfigure stdout -encoding utf-8
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
try {
    load {C:/orcad/Cadence/SPB_17.4/tools/bin/orDb_Dll_Tcl64.dll} DboTclWriteBasic
    package require json
    source [file join [file dirname [info script]] .. .. autoload drctoolMenu.tcl]
    set dir [file join [file dirname [info script]] test-output polish-native-[pid]]; file mkdir $dir
    set fixture [file join $dir test.dsn]
    file copy {C:/orcad/Cadence/SPB_17.4/tools/capture/samples/PCB-Layout/FullAdder/FULLADD.DSN} $fixture
    set session [DboTclHelper_sCreateSession]; set s [DboState]
    set c [DboTclHelper_sMakeCString $fixture]
    set design [$session GetDesignAndSchematics $c $s]; DboTclHelper_sDeleteCString $c
    set page [::xiaokai::drc::reviewPage $design FULLADD FULLADD]
    proc ::xiaokai::drc::activeDesign {} {return $::design}
    proc GetActivePage {} {return $::page}
    set ns ::xiaokai::drc
    set count [$page GetWireCount $s]
    puts [${ns}::commandExecute [${ns}::commandContext] [list ACTION aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa place_net_wires 2 {} {} -1 {}]]
    set context [${ns}::commandContext]; set json [json::json2dict [dict get $context json]]
    set selected {}; foreach row [dict get $json wires] {if {[dict get $row recent]} {lappend selected [dict get $row index]}}
    assert {[llength $selected] == 2}
    set layout "\{\"target_indices\":\[[join $selected ,]\]\}"
    set baseline [${ns}::commandWires $page]
    puts [${ns}::commandExecute $context [list ACTION bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb rename_wires 2 [${ns}::commandEncode "P1\nP2"] {} -1 [${ns}::commandEncode $layout]]]
    assert {[$page GetWireCount $s] == $count+2}
    set context [${ns}::commandContext]; set rows [dict get $context wires]
    foreach index $selected name {P1 P2} {
        set row [lindex $rows $index]
        assert {[dict get $row name] eq $name}
    }
    set json [json::json2dict [dict get $context json]]
    foreach index $selected {assert {[dict get [lindex [dict get $json wires] $index] recent]}}
    puts [${ns}::commandExecute $context [list ACTION cccccccccccccccccccccccccccccccc move_wires 0 {} {} -1 [${ns}::commandEncode "[string range $layout 0 end-1],\"spacing_factor\":0.5\}"]]]
    set context [${ns}::commandContext]
    set a [lindex [dict get $context wires] [lindex $selected 0]]; set b [lindex [dict get $context wires] [lindex $selected 1]]
    set learned [dict get [${ns}::commandPageStyle $page] spacing]
    assert {abs([lindex [dict get $a points] 0 1]-[lindex [dict get $b points] 0 1]) == max(10,int(round($learned*0.5/10))*10)}
    set baseline [${ns}::commandWires $page]
    assert {[catch {${ns}::commandExecute $context [list ACTION dddddddddddddddddddddddddddddddd rename_wires 2 [${ns}::commandEncode "DUP\nDUP"] {} -1 [${ns}::commandEncode $layout]]}]}
    assert {[${ns}::commandWires $page] eq $baseline}
    # mm display scale differs by 25.4 from inch display scale; the physical
    # database units per inch stay identical. Defaults and explicit mil spacing
    # must therefore be identical in both page display modes.
    proc metricPage {method args} {
        switch $method {GetPhysicalGranularity {return 3.937007874} GetDocUnitsPerInch {return 100.0} default {return [$::page $method {*}$args]}}
    }
    set metric [dict replace $context page metricPage]
    set auto [${ns}::commandLayout $metric {}]
    set explicit [${ns}::commandLayout $metric [${ns}::commandEncode {{"spacing_mil":400}}]]
    assert {[dict get $auto spacing] == $learned && [dict get $explicit spacing] == 40 && [dict get $explicit spacing_mil] == 400}
    # Exact click placement is checked in database coordinates after conversion;
    # reject occupied points instead of silently relocating elsewhere.
    set option [${ns}::commandLayout $context {}]
    set before [${ns}::commandWires $page]
    lassign [${ns}::commandSpace $page 160 80] x y
    dict set option _picked [list $x [expr {$y+20}]]
    set xy [${ns}::commandLayoutSpace $context 160 70 $option]
    assert {[lindex $xy 0] == $x && [lindex $xy 1] == $y+5}
    lassign [dict get $a points] point ignored
    dict set option _picked $point
    assert {[catch {${ns}::commandLayoutSpace $context 160 70 $option}]}
    assert {[${ns}::commandWires $page] eq $before}
    puts [${ns}::commandExecute $context [list ACTION eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee add_offpage_inputs 0 {} {} -1 [${ns}::commandEncode $layout]]]
    set context [${ns}::commandContext]
    puts [${ns}::commandExecute $context [list ACTION ffffffffffffffffffffffffffffffff move_wires 0 {} {} -1 [${ns}::commandEncode "[string range $layout 0 end-1],\"spacing_factor\":1.5\}"]]]
    set context [${ns}::commandContext]
    puts [${ns}::commandExecute $context [list ACTION aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa rename_wires 2 [${ns}::commandEncode "SIGNAL1\nSIGNAL2"] {} -1 [${ns}::commandEncode $layout]]]
    ${ns}::reviewCheckStatus [$session MarkAllLibForSave $design]
    ${ns}::reviewCheckStatus [$session SaveDesign $design]
    ${ns}::reviewCheckStatus [$session RemoveDesign $design]
    set c [DboTclHelper_sMakeCString $fixture]
    set design [$session GetDesignAndSchematics $c $s]; DboTclHelper_sDeleteCString $c
    set page [${ns}::reviewPage $design FULLADD FULLADD]
    set names [lmap r [${ns}::commandWires $page] {dict get $r name}]
    assert {"SIGNAL1" in $names && "SIGNAL2" in $names && [$page GetWireCount $s] == $count+2}
    set it [$page NewOffPageConnectorsIter $s]; set verified 0
    try {
        for {set off [$it NextOffPageConnector $s]} {$off ne "NULL"} {set off [$it NextOffPageConnector $s]} {
            set name [${ns}::cstring $off GetName]
            if {$name ni {SIGNAL1 SIGNAL2}} {continue}
            set wire [$off GetWire $s]
            assert {$wire ne "NULL" && [${ns}::cstring $wire GetNetName] eq $name}
            assert {[${ns}::commandXY [$off GetOffsetHotSpot $s]] eq [${ns}::commandXY [$wire GetStartPoint $s]]}
            incr verified
        }
    } finally {delete_DboPageOffPageConnectorsIter $it}
    assert {$verified == 2}
    puts "PASS: rename existing pair, stable recent identity, closer/farther relative spacing, attached input rename/move, duplicate refusal, metric physical conversion, picked/occupied geometry, persisted nets and native connections"
} on error {msg opts} {puts stderr [dict get $opts -errorinfo]; exit 1}
