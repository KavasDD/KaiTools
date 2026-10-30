fconfigure stdout -encoding utf-8
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
try {
    set ::env(CDSROOT) {C:/orcad/Cadence/SPB_17.4};set ::env(PATH) "C:/orcad/Cadence/SPB_17.4/tools/bin;$::env(PATH)"
    load {C:/orcad/Cadence/SPB_17.4/tools/bin/orDb_Dll_Tcl64.dll} DboTclWriteBasic
    source [file join [file dirname [info script]] .. .. autoload drctoolMenu.tcl]
    set ns ::xiaokai::drc;set state [DboState];set session [DboTclHelper_sCreateSession]
    set dir [file join [file dirname [info script]] test-output parts-native-[pid]-[clock clicks]];file mkdir $dir
    set fixture [file join $dir reference.dsn];file copy {D:/selfsoftware/out/style-reference.dsn} $fixture
    set c [DboTclHelper_sMakeCString $fixture];set design [$session GetDesignAndSchematics $c $state];DboTclHelper_sDeleteCString $c
    set page [${ns}::reviewPage $design MCU S03_PORT]
    proc GetActivePage {} {return $::page};proc ::xiaokai::drc::activeDesign {} {return $::design}
    proc indexOf {ref} {
        set context [::xiaokai::drc::commandContext];set i 0
        foreach item [dict get $context parts] {if {[lindex $item 1] eq $ref} {return $i};incr i};error "Missing part $ref"
    }
    proc run {action json} {return [::xiaokai::drc::commandExecute [::xiaokai::drc::commandContext] [list ACTION aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa $action 0 {} {} -1 [::xiaokai::drc::commandEncode $json]]]}
    set source [indexOf CN10];set original [${ns}::commandPartLogical [${ns}::snapshot $design]]
    set sourceRow [lindex [${ns}::commandPartTargets [${ns}::commandContext] [dict create target_indices [list $source]] $state] 0]
    set originalValue [${ns}::commandPartValue [dict get $sourceRow actor]]
    ${ns}::commandWritePartProperty [dict get $sourceRow actor] Value FIXTURE-OCCURRENCE
    ${ns}::commandWritePartProperty [dict get $sourceRow actor] {XK Custom Note} {fixture override}
    puts [run copy_parts [format {{"target_indices":[%d],"count":1}} $source]]
    set copy [indexOf CN11]
    proc rowOf {ref} {
        set context [::xiaokai::drc::commandContext]
        return [lindex [::xiaokai::drc::commandPartTargets $context [dict create target_indices [list [indexOf $ref]]] $::state] 0]
    }
    set clone [rowOf CN11];set cnId [dict get $clone id]
    assert {[${ns}::commandPartValue [dict get $clone actor]] eq [${ns}::commandPartValue [dict get [rowOf CN10] actor]]}
    assert {[${ns}::commandPartValue [dict get $clone actor]] eq "FIXTURE-OCCURRENCE"}
    assert {[${ns}::commandPartProperty [dict get $clone actor] {XK Custom Note}] eq {1 {fixture override}}}
    ${ns}::commandWritePartProperty [dict get [rowOf CN10] actor] Value $originalValue
    assert {[llength [dict get [${ns}::commandContext] parts]] == 38}
    # Move the big connector to an area with enough room to rotate about its origin.
    set context [${ns}::commandContext]
    set xy [${ns}::commandPartBlank $context {} 400 400 [list $cnId] {}]
    set current [dict get $clone box];lassign $xy x y
    set loc [dict get $clone location]
    set dx [expr {($x+150-[lindex $loc 0])*10}];set dy [expr {($y+150-[lindex $loc 1])*10}]
    puts [run move_parts [format {{"target_indices":[%d],"dx_mil":%d,"dy_mil":%d}} [indexOf CN11] $dx $dy]]
    set start [rowOf CN11]
    puts [run rotate_parts [format {{"target_indices":[%d],"angle_degrees":90}} [indexOf CN11]]]
    assert {[dict get [rowOf CN11] rotation] == ([dict get $start rotation]+1)%4}
    set rotated [rowOf CN11]
    puts [run mirror_parts [format {{"target_indices":[%d],"axis":"horizontal"}} [indexOf CN11]]]
    assert {[dict get [rowOf CN11] mirror] != [dict get $rotated mirror] || [dict get [rowOf CN11] rotation] != [dict get $rotated rotation]}
    puts [run set_part_property [format {{"target_indices":[%d],"property":"Value","values":["TEST-CONNECTOR"]}} [indexOf CN11]]]
    puts [run set_part_property [format {{"target_indices":[%d],"property":"PCB Footprint","values":["TEST-DIP"]}} [indexOf CN11]]]
    assert {[${ns}::commandPartValue [dict get [rowOf CN11] actor]] eq "TEST-CONNECTOR"}
    puts [run rename_parts [format {{"target_indices":[%d],"references":["CN99"]}} [indexOf CN11]]]
    assert {[dict get [rowOf CN99] id] == $cnId}
    # Verify mirror geometry, not only the native status/boolean: all orientations and axes.
    proc pinPoints {ref} {
        set id [dict get [rowOf $ref] id];set points {}
        foreach p [dict get [::xiaokai::drc::snapshot $::design] pins] {if {[dict get $p _part_id] == $id} {dict set points [dict get $p pin_number] [dict get $p _pin_point]}}
        return $points
    }
    set orientation [rowOf CN99]
    foreach angle {0 1 2 3} {
        set part [dict get [rowOf CN99] object];${ns}::reviewCheckStatus [$part SetRotation $angle]
        foreach axis {horizontal vertical} {
            set points [pinPoints CN99];lassign [dict get [rowOf CN99] box] l t r b;set ox [expr {($l+$r)/2}];set oy [expr {($t+$b)/2}]
            run mirror_parts [format {{"target_indices":[%d],"axis":"%s"}} [indexOf CN99] $axis]
            set reflected [pinPoints CN99]
            dict for {number xy} $points {
                lassign $xy x y
                set expected [expr {$axis eq "horizontal" ? [list [expr {2*$ox-$x}] $y] : [list $x [expr {2*$oy-$y}]]}]
                if {[dict get $reflected $number] ne $expected} {puts "MIRROR angle=$angle axis=$axis origin=$ox,$oy before=$xy after=[dict get $reflected $number] expected=$expected native=[dict get [rowOf CN99] rotation],[dict get [rowOf CN99] mirror]"}
                assert {[dict get $reflected $number] eq $expected}
            }
            run mirror_parts [format {{"target_indices":[%d],"axis":"%s"}} [indexOf CN99] $axis]
            assert {[pinPoints CN99] eq $points}
        }
    }
    set part [dict get [rowOf CN99] object]
    ${ns}::reviewCheckStatus [$part SetRotation [dict get $orientation rotation]]
    ${ns}::reviewCheckStatus [$part SetMirror [dict get $orientation mirror]]
    # Duplicate references, stale batches and rejected connected edits must leave the circuit intact.
    set prior [${ns}::commandPartLogical [${ns}::snapshot $design]]
    foreach action {copy_parts rename_parts} {
        assert {[catch {run $action [format {{"target_indices":[%d],"references":["CN10"]}} [indexOf CN99]]}]}
    }
    set old [rowOf CN10]
    assert {[catch {run rotate_parts [format {{"target_indices":[%d],"angle_degrees":90}} [indexOf CN10]]}]}
    assert {[dict get [rowOf CN10] location] eq [dict get $old location]}
    assert {[${ns}::commandPartLogical [${ns}::snapshot $design]] eq $prior}
    # Small component copies exercise row alignment, spacing and occurrence overrides.
    puts [run copy_parts [format {{"target_indices":[%d],"count":3,"layout":"row","spacing_mil":500}} [indexOf R285]]]
    set recent [dict get $::xiaokai::drc::commandFocus ids];assert {[llength $recent] == 3}
    set names {};foreach id $recent {foreach item [dict get [${ns}::commandContext] parts] {if {[lindex $item 0] == $id} {lappend names [lindex $item 1]}}}
    set targets [join [lmap ref $names {indexOf $ref}] ,]
    set first [lindex $names 0];set mid [lindex $names 1];set last [lindex $names 2]
    puts [run move_parts [format {{"target_indices":[%d],"dx_mil":0,"dy_mil":100}} [indexOf $mid]]]
    puts [run align_parts [format {{"target_indices":[%s],"alignment":"top"}} $targets]]
    assert {[lindex [dict get [rowOf $first] box] 1] == [lindex [dict get [rowOf $mid] box] 1]}
    puts [run distribute_parts [format {{"target_indices":[%s],"axis":"horizontal","gap_mil":300}} $targets]]
    set a [dict get [rowOf $first] box];set b [dict get [rowOf $mid] box];set c [dict get [rowOf $last] box]
    assert {[lindex $b 0]-[lindex $a 2] == 30 && [lindex $c 0]-[lindex $b 2] == 30}
    # Native post-write verification failure must delete every new part.
    set count [llength [dict get [${ns}::commandContext] parts]]
    rename ${ns}::commandPartModel ${ns}::savedPartModel
    proc ::xiaokai::drc::commandPartModel {context} {error "injected post-copy verification failure"}
    assert {[catch {run copy_parts [format {{"target_indices":[%d]}} [indexOf R285]]}]}
    rename ${ns}::commandPartModel {};rename ${ns}::savedPartModel ${ns}::commandPartModel
    assert {[llength [dict get [${ns}::commandContext] parts]] == $count}
    # Fail after rebuilding native caches: property and reference rollback must still work.
    rename ${ns}::commandPartModel ${ns}::savedPartModel
    proc ::xiaokai::drc::commandPartModel {context} {savedPartModel $context;error "injected post-edit failure"}
    foreach spec {{Value {"TEST-ROLLBACK"}} {MPN {"TEST-MPN"}}} {
        lassign $spec property values
        set beforeProperty [${ns}::commandPartProperty [dict get [rowOf CN99] actor] $property]
        assert {[catch {run set_part_property [format {{"target_indices":[%d],"property":"%s","values":[%s]}} [indexOf CN99] $property $values]}]}
        assert {[${ns}::commandPartProperty [dict get [rowOf CN99] actor] $property] eq $beforeProperty}
    }
    assert {[catch {run rename_parts [format {{"target_indices":[%d],"references":["CN100"]}} [indexOf CN99]]}]}
    assert {[dict get [rowOf CN99] id] == $cnId}
    rename ${ns}::commandPartModel {};rename ${ns}::savedPartModel ${ns}::commandPartModel
    # A lead with a native alias and offpage must follow its component, including rollback.
    set points {};foreach pin [dict get [${ns}::snapshot $design] pins] {if {[dict get $pin _part_id] == $cnId} {lappend points [dict get $pin _pin_point]}}
    lassign [lindex [lsort -integer -index 0 $points] 0] px py
    ${ns}::commandPlaceWires $page {XK_PART_LEAD} [expr {$px-60}] $py 60 10
    set context [${ns}::commandContext];set lead {}
    foreach wire [${ns}::commandWires $page] {if {"XK_PART_LEAD" in [dict get $wire names]} {set lead $wire}}
    assert {$lead ne ""}
    set off [${ns}::commandNewStyledOffpage $context $lead [lindex [dict get $lead points] 0] input $state]
    set offId [$off GetId $state];${ns}::commandPartModel $context
    set beforePoint [dict get [rowOf CN99] location]
    set priorWires [${ns}::commandPartLeadWires [${ns}::commandContext] [list [rowOf CN99]] [${ns}::snapshot $design] $state]
    assert {[llength $priorWires] == 1 && [llength [dict get [lindex $priorWires 0] symbols]] == 1}
    puts [run move_parts [format {{"target_indices":[%d],"dx_mil":0,"dy_mil":100}} [indexOf CN99]]]
    set newPoint [dict get [rowOf CN99] location]
    assert {[lindex $newPoint 0] == [lindex $beforePoint 0] && [lindex $newPoint 1] == [lindex $beforePoint 1]+10}
    set leadAfter [lindex [${ns}::commandPartLeadWires [${ns}::commandContext] [list [rowOf CN99]] [${ns}::snapshot $design] $state] 0]
    assert {[dict get $leadAfter id] == [dict get $lead id]}
    set sym [lindex [dict get $leadAfter symbols] 0]
    assert {[dict get $sym id] == $offId}
    ${ns}::commandVerifyOffpage [dict get $sym object] [dict get $leadAfter object] [lindex [dict get $leadAfter points] 0] input $state
    # Impossible location rolls back both part and leads; cache rebuilds must be harmless.
    assert {[catch {run move_parts [format {{"target_indices":[%d],"dx_mil":-10000,"dy_mil":-10000}} [indexOf CN99]]}]}
    assert {[dict get [rowOf CN99] location] eq $newPoint}
    set restored [lindex [${ns}::commandPartLeadWires [${ns}::commandContext] [list [rowOf CN99]] [${ns}::snapshot $design] $state] 0]
    assert {[dict get $restored points] eq [dict get $leadAfter points]}
    rename ${ns}::commandPartModel ${ns}::savedPartModel
    set ::failMoveOnce 1
    proc ::xiaokai::drc::commandPartModel {context} {
        set model [savedPartModel $context]
        if {$::failMoveOnce} {set ::failMoveOnce 0;error "injected post-move cache rebuild failure"}
        return $model
    }
    assert {[catch {run move_parts [format {{"target_indices":[%d],"dx_mil":0,"dy_mil":100}} [indexOf CN99]]} failure]}
    assert {![string match {*恢复失败*} $failure] && [dict get [rowOf CN99] location] eq $newPoint}
    rename ${ns}::commandPartModel {};rename ${ns}::savedPartModel ${ns}::commandPartModel
    set restored [lindex [${ns}::commandPartLeadWires [${ns}::commandContext] [list [rowOf CN99]] [${ns}::snapshot $design] $state] 0]
    assert {[dict get $restored points] eq [dict get $leadAfter points]}
    set sym [lindex [dict get $restored symbols] 0]
    ${ns}::commandVerifyOffpage [dict get $sym object] [dict get $restored object] [lindex [dict get $restored points] 0] input $state
    # Existing R285 has a physical connection to CN10: moving it alone must be refused.
    set old [rowOf R285]
    assert {[catch {run move_parts [format {{"target_indices":[%d],"dx_mil":100,"dy_mil":0}} [indexOf R285]]} rejection]}
    assert {[string match {*未选中*} $rejection] && [dict get [rowOf R285] location] eq [dict get $old location]}
    proc editedGeometry {} {
        set result {}
        foreach ref [concat CN99 $::names] {
            set row [rowOf $ref]
            lappend result [list $ref [dict get $row id] [dict get $row location] [dict get $row rotation] [dict get $row mirror] [::xiaokai::drc::commandPartValue [dict get $row actor]]]
        }
        foreach wire [::xiaokai::drc::commandWires $::page] {
            if {"XK_PART_LEAD" in [dict get $wire names]} {
                set symbols {};foreach sym [dict get $wire connectors] {lappend symbols [list [dict get $sym name] [dict get $sym rotation] [dict get $sym mirror]]}
                lappend result [list [dict get $wire id] [dict get $wire points] [dict get $wire names] $symbols]
            }
        }
        return $result
    }
    set savedGeometry [editedGeometry]
    set saved [${ns}::commandPartLogical [${ns}::snapshot $design]]
    ${ns}::reviewCheckStatus [$session MarkAllLibForSave $design];${ns}::reviewCheckStatus [$session SaveDesign $design]
    ${ns}::reviewCheckStatus [$session RemoveDesign $design]
    set c [DboTclHelper_sMakeCString $fixture];set design [$session GetDesignAndSchematics $c $state];DboTclHelper_sDeleteCString $c
    set page [${ns}::reviewPage $design MCU S03_PORT]
    assert {[${ns}::commandPartLogical [${ns}::snapshot $design]] eq $saved}
    assert {[editedGeometry] eq $savedGeometry}
    assert {[${ns}::commandPartValue [dict get [rowOf CN99] actor]] eq "TEST-CONNECTOR"}
    assert {[${ns}::commandPartProperty [dict get [rowOf CN99] actor] {PCB Footprint}] eq {1 TEST-DIP}}
    puts "PASS: eight native component tools, automatic references, copied occurrence values, collision refusal, connected rotation refusal, failed-copy rollback, save/reopen partition and properties"
} on error {msg opts} {puts stderr [dict get $opts -errorinfo];exit 1}
exit 0
