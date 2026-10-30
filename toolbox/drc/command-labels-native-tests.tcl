fconfigure stdout -encoding utf-8
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
try {
    load {C:/orcad/Cadence/SPB_17.4/tools/bin/orDb_Dll_Tcl64.dll} DboTclWriteBasic
    source [file join [file dirname [info script]] .. .. autoload drctoolMenu.tcl]
    set state [DboState];set session [DboTclHelper_sCreateSession];set ns ::xiaokai::drc
    set dir [file join [file dirname [info script]] test-output labels-native-[pid]-[clock clicks]];file mkdir $dir
    set fixture [file join $dir reference.dsn]
    file copy {D:/selfsoftware/out/style-reference.dsn} $fixture
    set c [DboTclHelper_sMakeCString $fixture];set design [$session GetDesignAndSchematics $c $state];DboTclHelper_sDeleteCString $c
    set page [${ns}::reviewPage $design MCU S03_PORT]
    proc GetActivePage {} {return $::page}
    proc ::xiaokai::drc::activeDesign {} {return $::design}
    proc labelAction {oldNames newNames {kind offpage}} {
        set context [::xiaokai::drc::commandContext];set targets {};set i 0
        foreach name $oldNames {
            set matches {};set i 0
            foreach row [dict get $context labels] {if {[dict get $row name] eq $name && [dict get $row kind] eq $kind} {lappend matches $i};incr i}
            assert {[llength $matches] == 1};lappend targets [lindex $matches 0]
        }
        set options "\{\"label_indices\":\[[join $targets ,]\]\}"
        ::xiaokai::drc::commandExecute $context [list ACTION cccccccccccccccccccccccccccccccc rename_net_labels [llength $targets] [::xiaokai::drc::commandEncode [join $newNames \n]] {} -1 [::xiaokai::drc::commandEncode $options]]
    }
    proc geometry {} {
        set state [DboState];set rows {};set labels {}
        set views [$::design NewViewsIter $state $::IterDefs_SCHEMATICS]
        try {
            for {set view [$views NextView $state]} {$view ne "NULL"} {set view [$views NextView $state]} {
                set sch [DboViewToDboSchematic $view];set it [$sch NewPagesIter $state]
                try {
                    for {set p [$it NextPage $state]} {$p ne "NULL"} {set p [$it NextPage $state]} {
                        set prefix [list [::xiaokai::drc::cstring $sch GetName] [::xiaokai::drc::cstring $p GetName]]
                        foreach r [::xiaokai::drc::commandWires $p] {
                            lappend rows [list $prefix wire [dict get $r id] [dict get $r points]]
                            foreach off [dict get $r connectors] {lappend rows [list $prefix connector [dict get $off id] [dict get $off rotation] [dict get $off mirror] [dict get $off hot]]}
                        }
                        foreach label [::xiaokai::drc::commandNetLabels $p] {
                            set identity [list $prefix [dict get $label id] [dict get $label kind] [dict get $label point] [dict get $label wire_id]]
                            lappend rows $identity;lappend labels [list $identity [dict get $label name]]
                        }
                    }
                } finally {delete_DboSchematicPagesIter $it}
            }
        } finally {delete_DboLibViewsIter $views;$state -delete}
        return [list [lsort $rows] [lsort $labels]]
    }
    set baselineGeometry [lindex [geometry] 0]
    set original [${ns}::commandPinPartition [${ns}::snapshot $design]]
    assert {$original eq [${ns}::commandPinPartition [${ns}::snapshot $design]]}
    set old {MCU_MDI0 MCU_MDI1 MCU_MDI2};set new {MCU_M0 MCU_M1 MCU_M2}
    puts [labelAction $old $new]
    set after [${ns}::commandPinPartition [${ns}::snapshot $design]]
    assert {$after eq $original}
    set left {};foreach row [${ns}::commandWires $page] {foreach name [dict get $row names] {if {$name in {MCU_DIO0 MCU_DIO1 MCU_DIO2}} {lappend left $name}}}
    assert {[lsort -unique $left] eq {MCU_DIO0 MCU_DIO1 MCU_DIO2}}
    puts [labelAction $new $new]
    assert {[catch {labelAction $new {MCU_DIO3 MCU_M1 MCU_M2}} failure] && [string match *已存在* $failure]}
    rename ${ns}::commandSetLabelName ${ns}::realSetLabelName
    set ::calls 0
    proc ${ns}::commandSetLabelName {object name} {incr ::calls;if {$::calls == 2} {error INJECTED_NAME_FAILURE};realSetLabelName $object $name}
    assert {[catch {labelAction $new $old} failure] && [string match *INJECTED* $failure]}
    rename ${ns}::commandSetLabelName {};rename ${ns}::realSetLabelName ${ns}::commandSetLabelName
    set found {};foreach row [${ns}::commandNetLabels $page] {if {[dict get $row name] in $new} {lappend found [dict get $row name]}}
    assert {[lsort -unique $found] eq $new}
    assert {[${ns}::commandPinPartition [${ns}::snapshot $design]] eq $original}
    assert {[lindex [geometry] 0] eq $baselineGeometry}
    # A selected alias group is supported too, and changing it back is lossless.
    puts [labelAction {MCU_DIO0 MCU_DIO1 MCU_DIO2} {ALIAS_T0 ALIAS_T1 ALIAS_T2} alias]
    puts [labelAction {ALIAS_T0 ALIAS_T1 ALIAS_T2} {MCU_DIO0 MCU_DIO1 MCU_DIO2} alias]
    set renamed [geometry]
    assert {[lindex $renamed 0] eq $baselineGeometry}
    assert {[${ns}::commandPinPartition [${ns}::snapshot $design]] eq $original}
    # Stale context and fabricated indices must never edit native objects.
    set context [${ns}::commandContext];dict set context revision stale
    set fields [list ACTION cccccccccccccccccccccccccccccccc rename_net_labels 1 [${ns}::commandEncode BAD_NAME] {} -1 [${ns}::commandEncode {{"label_indices":[0]}}]]
    assert {[catch {${ns}::commandExecute $context $fields} failure]}
    set context [${ns}::commandContext];lset fields 7 [${ns}::commandEncode {{"label_indices":[999999]}}]
    assert {[catch {${ns}::commandExecute $context $fields} failure]}
    assert {[geometry] eq $renamed}
    ${ns}::reviewCheckStatus [$session MarkAllLibForSave $design]
    ${ns}::reviewCheckStatus [$session SaveDesign $design]
    ${ns}::reviewCheckStatus [$session RemoveDesign $design]
    set c [DboTclHelper_sMakeCString $fixture];set design [$session GetDesignAndSchematics $c $state];DboTclHelper_sDeleteCString $c
    set page [${ns}::reviewPage $design MCU S03_PORT]
    set reopened [geometry]
    # Capture assigns alias IDs on load; wire/connector IDs are persisted.
    proc persistedGeometry {data} {
        set rows {};set labels {}
        foreach r [lindex $data 0] {if {[lindex $r 2] eq "alias"} {lset r 1 alias};lappend rows $r}
        foreach r [lindex $data 1] {if {[lindex $r 0 2] eq "alias"} {lset r 0 1 alias};lappend labels $r}
        return [list [lsort $rows] [lsort $labels]]
    }
    assert {[persistedGeometry $reopened] eq [persistedGeometry $renamed]}
    proc persistedPartition {partition} {
        set pins {};set groups {}
        foreach row [lindex $partition 0] {lset row 0 4 pin;lappend pins $row}
        foreach group [lindex $partition 1] {
            set members {};foreach id $group {lset id 4 pin;lappend members $id};lappend groups [lsort $members]
        }
        return [list [lsort $pins] [lsort $groups]]
    }
    assert {[persistedPartition [${ns}::commandPinPartition [${ns}::snapshot $design]]] eq [persistedPartition $original]}
    assert {[persistedPartition [${ns}::commandPinPartition [${ns}::snapshot $design]]] eq [persistedPartition $original]}
    puts "PASS: actual multi-name connected nets, offpage/alias precision, cross-page propagation, pin partition, geometry/IDs, idempotence, collision, injected rollback, stale/invalid targets, save/reopen"

} on error {msg opts} {puts stderr [dict get $opts -errorinfo];exit 1}
