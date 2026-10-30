fconfigure stdout -encoding utf-8
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
proc persistedWires {rows} {
    set result {}
    foreach row $rows {
        dict unset row object
        dict set row aliases [lmap a [dict get $row aliases] {lrange $a 1 end}]
        dict set row connectors [lmap c [dict get $row connectors] {dict remove $c object}]
        lappend result $row
    }
    return $result
}
try {
    load {C:/orcad/Cadence/SPB_17.4/tools/bin/orDb_Dll_Tcl64.dll} DboTclWriteBasic
    source [file join [file dirname [info script]] .. .. autoload drctoolMenu.tcl]
    package require json
    set ns ::xiaokai::drc;set state [DboState];set session [DboTclHelper_sCreateSession]
    set dir [file join [file dirname [info script]] test-output style-native-[pid]-[clock clicks]];file mkdir $dir
    set fixture [file join $dir reference.dsn]
    if {[info exists ::env(XK_STYLE_FIXTURE)]} {set source $::env(XK_STYLE_FIXTURE);set sch MCU;set sheet S03_PORT} else {set source {C:/orcad/Cadence/SPB_17.4/tools/capture/samples/PCB-Layout/FullAdder/FULLADD.DSN};set sch FULLADD;set sheet FULLADD}
    file copy $source $fixture
    set c [DboTclHelper_sMakeCString $fixture];set design [$session GetDesignAndSchematics $c $state];DboTclHelper_sDeleteCString $c
    set page [${ns}::reviewPage $design $sch $sheet]
    proc GetActivePage {} {return $::page}
    proc ::xiaokai::drc::activeDesign {} {return $::design}
    proc run {action options {names {}} {text {}} {index -1}} {
        return [::xiaokai::drc::commandExecute [::xiaokai::drc::commandContext] [list ACTION bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb $action [llength $names] [::xiaokai::drc::commandEncode [join $names \n]] [::xiaokai::drc::commandEncode $text] $index [::xiaokai::drc::commandEncode $options]]]
    }
    set baseline [${ns}::commandWires $page]
    set style [${ns}::commandPageStyle $page];puts "LEARNED [dict remove $style input_template]"
    set expectedSpacing [dict get $style spacing]
    if {[info exists ::env(XK_STYLE_FIXTURE)]} {assert {$expectedSpacing == 10 && [dict get $style votes] >= 3 && [dict get $style input_template] ne "NULL"}}
    set before [$page GetOffPageConnectorCount $state]
    proc assertSingleLabel {row state} {
        assert {[llength [dict get $row aliases]] == 1}
        set off [lindex [lindex [::xiaokai::drc::commandWireAttachments $row $state] 0] 0]
        set it [$off NewDisplayPropsIter $state]
        try {
            for {set prop [$it NextProp $state]} {$prop ne "NULL"} {set prop [$it NextProp $state]} {
                if {[::xiaokai::drc::cstring $prop GetName] eq "Name"} {assert {[$prop GetDisplayType $state] == 0}}
            }
        } finally {delete_DboDisplayPropsIter $it}
    }
    puts [run place_net_wires {{"inputs":true}} {STYLE_A STYLE_B STYLE_C STYLE_D STYLE_E STYLE_F STYLE_G STYLE_H STYLE_I STYLE_J}]
    set context [${ns}::commandContext];set targets {};set i 0;set priorY "";set created {}
    foreach row [dict get $context wires] {
        if {[string match STYLE_* [dict get $row name]]} {
            lappend targets $i;lappend created $row
            set off [lindex [lindex [${ns}::commandWireAttachments $row $state] 0] 0]
            assert {[${ns}::cstring [$off GetSymbol $state] GetName] eq "OFFPAGELEFT-L" && [$off GetRotation $state] == 0 && [$off GetMirror $state] == 1}
            set point [lindex [dict get $row points] 0]
            assert {[${ns}::commandGraphicPoint $off {0 10}] eq $point}
            ${ns}::commandVerifyOffpage $off [dict get $row object] $point input $state
            assertSingleLabel $row $state
            if {$priorY ne ""} {assert {[lindex $point 1]-$priorY == $expectedSpacing}}
            set priorY [lindex $point 1]
        }
        incr i
    }
    assert {[llength $targets] == 10 && [$page GetOffPageConnectorCount $state] == $before+10}
    assert {[dict get [${ns}::commandPageStyle $page] spacing] == $expectedSpacing}
    set options "\{\"target_indices\":\[[join $targets ,]\]\}"
    # Reproduce the actual live failure: old R/180deg is 30 DB units left of
    # wire start, completely detached. Same-name unique targets can be repaired.
    set row [lindex $created 0];set off [lindex [lindex [${ns}::commandWireAttachments $row $state] 0] 0]
    set point [lindex [dict get $row points] 0]
    # Native deletion requires Disconnect first, just as the Capture editor does.
    # Otherwise the schematic net retains a freed symbol until its next rebuild.
    ${ns}::reviewCheckStatus [${ns}::commandDeleteOffpage $page $off]
    lassign [${ns}::commandInputSymbol $design $state OFFPAGELEFT-R] wrongSymbol hot
    set c [DboTclHelper_sMakeCString [dict get $row name]]
    set p [DboTclHelper_sMakeCPoint [expr {[lindex $point 0]-30}] [expr {[lindex $point 1]-10}]]
    set wrong [$page NewOffPageConnector $state $c $wrongSymbol $p 2 0]
    DboTclHelper_sDeleteCString $c;DboTclHelper_sDeleteCPoint $p
    assert {[$wrong GetWire $state] eq "NULL" && [catch {${ns}::commandVerifyOffpage $wrong [dict get $row object] $point input $state}]}
    puts [run add_offpage_inputs $options]
    assert {[$page GetOffPageConnectorCount $state] == $before+10}
    # Stage a native failure after some new objects exist: original objects survive.
    rename ${ns}::commandNewStyledOffpage ${ns}::realNewOffpage
    set ::calls 0
    proc ${ns}::commandNewStyledOffpage {args} {incr ::calls;if {$::calls == 2} {error INJECTED_FAILURE};realNewOffpage {*}$args}
    set original [${ns}::commandWires $page]
    assert {[catch {run set_offpage_direction "[string range $options 0 end-1],\"signal_type\":\"output\"\}"} msg] && [string match *INJECTED* $msg]}
    # EvalPage may replace SWIG pointers while preserving native object IDs.
    assert {[persistedWires [${ns}::commandWires $page]] eq [persistedWires $original] && [$page GetOffPageConnectorCount $state] == $before+10}
    assert {[dict size $::xiaokai::drc::commandDeletedOffpages] == 0}
    rename ${ns}::commandNewStyledOffpage {};rename ${ns}::realNewOffpage ${ns}::commandNewStyledOffpage
    puts [run set_offpage_direction "[string range $options 0 end-1],\"signal_type\":\"output\"\}"]
    puts [run add_offpage_inputs $options]
    puts [run move_wires "[string range $options 0 end-1],\"spacing_mil\":100\}"]
    set names {};for {set i 0} {$i<10} {incr i} {lappend names STYLE_NEW_$i}
    puts [run rename_wires $options $names]
    # Target one real part by current native ID, with the exact old Value recorded.
    set context [${ns}::commandContext];set partIndex 0
    if {[info exists ::env(XK_STYLE_FIXTURE)]} {
        set partIndex -1;set i 0
        foreach item [dict get $context parts] {if {[lindex $item 1] eq "CN10"} {set partIndex $i;break};incr i}
        assert {$partIndex >= 0}
    }
    if {![info exists ::env(XK_STYLE_FIXTURE)]} {
        set i 0;set it [$page NewPartInstsIter $state]
        for {set p [$it NextPartInst $state]} {$p ne "NULL"} {set p [$it NextPartInst $state]} {if {[$p IsPrimitive $state]} {set partIndex $i;break};incr i}
        delete_DboPagePartInstsIter $it
    }
    set target [lindex [dict get $context parts] $partIndex];lassign $target partId ref
    set it [$page NewPartInstsIter $state]
    for {set part [$it NextPartInst $state]} {$part ne "NULL"} {set part [$it NextPartInst $state]} {if {[$part GetId $state] == $partId} {break}}
    delete_DboPagePartInstsIter $it
    set choices [dict get [${ns}::commandPartOccurrences $design $page] $partId]
    set actor [lindex [lindex $choices 0] 0]
    set value [${ns}::commandPartValue $actor];set box [${ns}::reviewRect [$part GetOffsetBoundingBox $state]]
    puts [run set_part_value {{}} {} con-200 $partIndex]
    assert {[${ns}::commandPartValue $actor] eq "con-200" && [$part GetId $state] == $partId && [${ns}::reviewRect [$part GetOffsetBoundingBox $state]] eq $box}
    ${ns}::reviewCheckStatus [$session MarkAllLibForSave $design];${ns}::reviewCheckStatus [$session SaveDesign $design];${ns}::reviewCheckStatus [$session RemoveDesign $design]
    set c [DboTclHelper_sMakeCString $fixture];set design [$session GetDesignAndSchematics $c $state];DboTclHelper_sDeleteCString $c
    set page [${ns}::reviewPage $design $sch $sheet];set verified 0
    set choices [dict get [${ns}::commandPartOccurrences $design $page] $partId]
    set actor [lindex [lindex $choices 0] 0]
    assert {[${ns}::commandPartValue $actor] eq "con-200"}
    puts [run set_part_value {{}} {} $value $partIndex]
    foreach row [${ns}::commandWires $page] {
        if {[dict get $row name] ni $names} {continue}
        set off [lindex [lindex [${ns}::commandWireAttachments $row $state] 0] 0]
        ${ns}::commandVerifyOffpage $off [dict get $row object] [lindex [dict get $row points] 0] input $state
        assertSingleLabel $row $state
        incr verified
    }
    assert {$verified == 10 && [$page GetOffPageConnectorCount $state] == $before+10}
    puts "PASS: native drawing-style learning, 10-wire creation, rendered tip/hotspot/wire equality, single visible name, mirror/template, idempotence, staged failure rollback, output/input repair, move, rename, Value readback/restore, save/reopen"
} on error {msg opts} {puts stderr [dict get $opts -errorinfo];exit 1}
