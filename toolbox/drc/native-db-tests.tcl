# Native Dbo DLL in a separate Tcl process. No Capture window or live design.
set repo [file normalize [file join [file dirname [info script]] .. ..]]
set spb {C:/orcad/Cadence/SPB_17.4}
fconfigure stdout -encoding utf-8; fconfigure stderr -encoding utf-8
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
try {
    load [file join $spb tools bin orDb_Dll_Tcl64.dll] DboTclWriteBasic
    source [file join $repo autoload drctoolMenu.tcl]
    set ns ::xiaokai::drc
    set directory [file join $repo toolbox drc test-output native-db-[pid]-[clock milliseconds]]
    file mkdir $directory
    set fixture [file join $directory fulladd.dsn]
    file copy [file join $spb tools capture samples PCB-Layout FullAdder FULLADD.DSN] $fixture
    set session [DboTclHelper_sCreateSession]; set s [DboState]
    set name [DboTclHelper_sMakeCString $fixture]
    set design [$session GetDesignAndSchematics $name $s]
    DboTclHelper_sDeleteCString $name
    assert {$design ne "NULL" && [$s OK]}
    set page [${ns}::reviewPage $design FULLADD FULLADD]
    puts [list PAGE width [$page GetPageWidth] height [$page GetPageHeight] scale [$page GetPhysicalGranularity]]
    set it [$page NewPartInstsIter $s]; set part [$it NextPartInst $s]
    while {$part ne "NULL" && ![$part IsPrimitive $s]} {set part [$it NextPartInst $s]}
    delete_DboPagePartInstsIter $it; assert {$part ne "NULL"}
    set loc [DboTclHelper_sMakeCPoint 700 450]
    ${ns}::reviewCheckStatus [$part SetLocation $loc]; DboTclHelper_sDeleteCPoint $loc
    set pins [$part NewPinsIter $s]; set pin [$pins NextPin $s]
    set target [dict create _part_id [$part GetId $s] _pin_id [$pin GetId $s] pin_number [${ns}::cstring $pin GetPinNumber 1] refdes [${ns}::cstring $part GetReference]]
    set originalNc [$pin GetIsNoConnect $s]
    assert {$originalNc in {0 1}}
    ${ns}::reviewCheckStatus [$pin SetIsNoConnect 1]
    assert {[$pin GetIsNoConnect $s] == 1}
    ${ns}::reviewCheckStatus [$pin SetIsNoConnect $originalNc]
    set component [${ns}::componentInfo $part $part]
    assert {[dict exists $component part_number] && [dict exists $component footprint]}
    delete_DboPartInstPinsIter $pins
    set row [dict create rule_id unconnected_pin hierarchy_path / _schematic FULLADD sheet_name FULLADD \
        _targets [list $target] _pin_specific 1 message test]
    set checked [dict create design $design source $fixture review_contexts {{path / schematic FULLADD}}]
    set candidate [${ns}::reviewCandidate $row $checked]
    dict set candidate text "\u68c0\u67e5\u5f15\u811a"
    # Surround the fault with a graphic; it must not displace Text.
    set rect [DboTclHelper_sMakeCRect 600 400 900 650]
    set origin [DboTclHelper_sMakeCPoint 0 0]
    set frame [$page NewGraphicBoxInst $s $rect $origin 0]
    DboTclHelper_sDeleteCRect $rect; DboTclHelper_sDeleteCPoint $origin
    assert {$frame ne "NULL" && [$s OK]}
    set fault [${ns}::reviewFaultPoint $page $row [dict get $candidate part_id]]
    assert {[catch {${ns}::reviewFaultPoint $page $row -1}]}
    assert {[catch {${ns}::reviewFaultPoint $page [dict replace $row _targets {}] [dict get $candidate part_id]}]}
    set before [${ns}::reviewConnectivity $design]
    set entry [${ns}::reviewPlacement $candidate $checked]
    assert {[list [dict get $entry x] [dict get $entry y]] eq $fault}
    ${ns}::reviewCreate $entry $checked native-db-test
    set owned [${ns}::reviewOwned $design]
    assert {[llength $owned] == 1 && [dict get [lindex $owned 0] unchanged]}
    assert {[[dict get [lindex $owned 0] inst] GetColor $s] == $::DboValue_COLOR8}
    # Existing Text and batch reservations must not displace the next note.
    set second [${ns}::reviewPlacement $candidate $checked 1 [list $entry]]
    assert {[dict get $entry text_rect] eq [dict get $second text_rect]}
    ${ns}::reviewCreate $second $checked native-db-second
    assert {[${ns}::reviewConnectivity $design] eq $before}
    puts [list PLACED [dict get $entry fault_point] [dict get $entry text_rect] [dict get $second text_rect]]
    ${ns}::reviewCheckStatus [$session MarkAllLibForSave $design]
    ${ns}::reviewCheckStatus [$session SaveDesign $design]
    ${ns}::reviewCheckStatus [$session RemoveDesign $design]
    set name [DboTclHelper_sMakeCString $fixture]
    set design [$session GetDesignAndSchematics $name $s]; DboTclHelper_sDeleteCString $name
    assert {$design ne "NULL" && [$s OK]}
    set owned [${ns}::reviewOwned $design]; assert {[llength $owned] == 2}
    set actual {}
    foreach record $owned {
        assert {[dict get $record unchanged] && [${ns}::reviewText [dict get $record inst]] eq [dict get $entry text]}
        assert {[[dict get $record inst] GetColor $s] == $::DboValue_COLOR8}
        lappend actual [${ns}::reviewGraphicRect [dict get $record inst] $s]
    }
    assert {[lsort $actual] eq [lsort [list [dict get $entry text_rect] [dict get $second text_rect]]]}
    set removed [${ns}::reviewRemove $design]
    assert {[dict get $removed removed] == 2}
    puts "PASS: native DLL, isolated DSN, fresh exact fault point, red Text, no avoidance, unchanged connectivity, red color and position after save/reopen, removal"
    $s -delete; DboTclHelper_sDeleteSession $session
} on error {msg opts} {puts stderr [dict get $opts -errorinfo]; exit 1}
