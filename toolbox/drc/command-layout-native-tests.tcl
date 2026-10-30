fconfigure stdout -encoding utf-8
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
try {
    load {C:/orcad/Cadence/SPB_17.4/tools/bin/orDb_Dll_Tcl64.dll} DboTclWriteBasic
    source [file join [file dirname [info script]] .. .. autoload drctoolMenu.tcl]
    set dir [file join [file dirname [info script]] test-output layout-native-[pid]]; file mkdir $dir
    set fixture [file join $dir test.dsn]
    file copy {C:/orcad/Cadence/SPB_17.4/tools/capture/samples/PCB-Layout/FullAdder/FULLADD.DSN} $fixture
    set session [DboTclHelper_sCreateSession]; set s [DboState]
    set c [DboTclHelper_sMakeCString $fixture]
    set design [$session GetDesignAndSchematics $c $s]; DboTclHelper_sDeleteCString $c
    set page [::xiaokai::drc::reviewPage $design FULLADD FULLADD]
    proc ::xiaokai::drc::activeDesign {} {return $::design}
    proc GetActivePage {} {return $::page}
    set ns ::xiaokai::drc
    proc action {action id count {options {}}} {
        set context [::xiaokai::drc::commandContext]
        set fields [list ACTION $id $action $count {} {} -1 [::xiaokai::drc::commandEncode $options]]
        return [::xiaokai::drc::commandExecute $context $fields]
    }
    set before [$page GetWireCount $s]
    puts [action place_net_wires 11111111111111111111111111111111 4]
    set context [${ns}::commandContext]
    set index 0; set reference -1
    foreach row [dict get $context wires] {if {[dict get $row name] eq "XKA_111111111111_2"} {set reference $index}; incr index}
    assert {$reference >= 0}
    puts [action place_net_wires 22222222222222222222222222222222 2 "\{\"near_index\":$reference,\"direction\":\"right\",\"clearance_mil\":800,\"spacing_mil\":800\}"]
    assert {[$page GetWireCount $s] == $before+6}
    set context [${ns}::commandContext]; set targets {}; set moving {}; set index 0
    foreach row [dict get $context wires] {
        if {[string match XKA_* [dict get $row name]]} {lappend targets $index}
        if {[string match XKA_222* [dict get $row name]]} {lappend moving $index}
        incr index
    }
    assert {[llength $targets] == 6 && [llength $moving] == 2}
    set move "\{\"target_indices\":\[[join $moving ,]\],\"near_index\":$reference,\"direction\":\"right\",\"clearance_mil\":1200,\"spacing_mil\":1200\}"
    puts [action move_wires 33333333333333333333333333333333 0 $move]
    assert {[$page GetWireCount $s] == $before+6}
    set movedRows [${ns}::commandTargetRows [${ns}::commandContext] [${ns}::commandLayout [${ns}::commandContext] [${ns}::commandEncode $move] 1]]
    set ay [lindex [dict get [lindex $movedRows 0] points] 0 1]
    set by [lindex [dict get [lindex $movedRows 1] points] 0 1]
    assert {abs($ay-$by) == 120}
    lassign [${ns}::commandBounds [dict get [lindex [dict get [${ns}::commandContext] wires] $reference] points]] rl rt rr rb
    foreach row $movedRows {assert {[lindex [${ns}::commandBounds [dict get $row points]] 0] >= $rr+120}}
    # Simulate a failure after one wire has moved, and require original IDs,
    # points and alias positions to be restored for the complete batch.
    set baseline [${ns}::commandWires $page]
    rename ${ns}::commandSetWire ${ns}::nativeSetWire
    set ::setCalls 0
    proc ${ns}::commandSetWire {row points aliases} {
        incr ::setCalls
        if {$::setCalls == 2} {error INJECTED_SECOND_WIRE_FAILURE}
        return [nativeSetWire $row $points $aliases]
    }
    set failed [catch {action move_wires 77777777777777777777777777777777 0 [string map {1200 1600} $move]} failure]
    rename ${ns}::commandSetWire {}; rename ${ns}::nativeSetWire ${ns}::commandSetWire
    assert {$failed && [string match *INJECTED_SECOND_WIRE_FAILURE* $failure]}
    assert {[${ns}::commandWires $page] eq $baseline}
    # Reject an impossible batch and invalid targets without changing the page.
    assert {[catch {action place_net_wires 88888888888888888888888888888888 32 {{"spacing_mil":5000}}} spaceFailure]}
    assert {[string match *空白* $spaceFailure]}
    assert {[catch {action add_offpage_inputs 88888888888888888888888888888888 0 {{"target_indices":[9999]}}} targetFailure]}
    assert {[string match *目标导线不存在* $targetFailure]}
    assert {[$page GetWireCount $s] == $before+6}
    set ports [$page GetOffPageConnectorCount $s]
    set inputs "\{\"target_indices\":\[[join $targets ,]\]\}"
    puts [action add_offpage_inputs 44444444444444444444444444444444 0 $inputs]
    assert {[$page GetOffPageConnectorCount $s] == $ports+6}
    puts [action add_offpage_inputs 55555555555555555555555555555555 0 $inputs]
    assert {[$page GetOffPageConnectorCount $s] == $ports+6}
    puts [action move_wires 66666666666666666666666666666666 0 $move]
    assert {[$page GetOffPageConnectorCount $s] == $ports+6}
    ${ns}::reviewCheckStatus [$session MarkAllLibForSave $design]
    ${ns}::reviewCheckStatus [$session SaveDesign $design]
    ${ns}::reviewCheckStatus [$session RemoveDesign $design]
    set c [DboTclHelper_sMakeCString $fixture]
    set design [$session GetDesignAndSchematics $c $s]; DboTclHelper_sDeleteCString $c
    set page [${ns}::reviewPage $design FULLADD FULLADD]
    assert {[$page GetWireCount $s] == $before+6 && [$page GetOffPageConnectorCount $s] == $ports+6}
    set it [$page NewOffPageConnectorsIter $s]; set checked 0
    try {
        for {set off [$it NextOffPageConnector $s]} {$off ne "NULL"} {set off [$it NextOffPageConnector $s]} {
            set name [${ns}::cstring $off GetName]
            if {![string match XKA_* $name]} {continue}
            set wire [$off GetWire $s]
            puts "PORT $name WIRE $wire"
            assert {$wire ne "NULL"}
            assert {[${ns}::cstring $wire GetNetName] eq $name}
            set symbol [$off GetSymbol $s]
            set key [DboTclHelper_sMakeCString OFFPAGELEFT-L]
            set inputSymbol [$design GetOffPageSymbol $key $s]; DboTclHelper_sDeleteCString $key
            assert {[${ns}::cstring $symbol GetName] eq "OFFPAGELEFT-L" && [[$inputSymbol GetPin $s] GetPinType $s] == $::DboValue_DBO_IN}
            assert {[$off GetRotation $s] == 0 && [$off GetMirror $s] == 1}
            ${ns}::commandVerifyOffpage $off $wire [${ns}::commandXY [$wire GetStartPoint $s]] input $s
            assert {[${ns}::commandXY [$off GetOffsetHotSpot $s]] eq [${ns}::commandXY [$wire GetStartPoint $s]]}
            incr checked
        }
    } finally {delete_DboPageOffPageConnectorsIter $it}
    assert {$checked == 6}
    puts "PASS: reference placement, explicit spacing, moving existing wires and attached offpages, duplicate suppression, native connections after save/reopen"
} on error {msg opts} {puts stderr [dict get $opts -errorinfo]; exit 1}
