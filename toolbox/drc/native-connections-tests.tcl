# Read the official sample in an isolated native database. No GUI, save or DRC.
set repo [file normalize [file join [file dirname [info script]] .. ..]]
set spb {C:/orcad/Cadence/SPB_17.4}
fconfigure stdout -encoding utf-8; fconfigure stderr -encoding utf-8
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
try {
    load [file join $spb tools bin orDb_Dll_Tcl64.dll] DboTclWriteBasic
    source [file join $repo autoload drctoolMenu.tcl]
    set ns ::xiaokai::drc
    set directory [file join $repo toolbox drc test-output native-connections-[pid]]
    file mkdir $directory
    set fixture [file join $directory fulladd.dsn]
    file copy -force [file join $spb tools capture samples PCB-Layout FullAdder FULLADD.DSN] $fixture
    set f [open $fixture rb]; set before [zlib crc32 [read $f]]; close $f
    set session [DboTclHelper_sCreateSession]; set s [DboState]
    set name [DboTclHelper_sMakeCString $fixture]
    set design [$session GetDesignAndSchematics $name $s]; DboTclHelper_sDeleteCString $name
    assert {$design ne "NULL" && [$s OK]}
    set model [${ns}::snapshot $design]
    set nets {}; set tested 0; set cross 0
    foreach pin [dict get $model pins] {
        if {![dict get $pin is_primitive] || [dict get $pin flat_net] eq ""} {continue}
        set flat [dict get $pin flat_net]
        if {[dict exists $nets $flat]} {continue}; dict set nets $flat 1
        set facts [${ns}::connectionFacts [dict create _targets [list $pin]] $model]
        set endpoints [dict get [lindex [dict get $facts networks] 0] endpoints]
        assert {[llength $endpoints] > 0}
        set paths {}
        foreach endpoint $endpoints {
            assert {[dict get $endpoint flat_net] eq $flat && [dict get $endpoint is_primitive]}
            assert {[dict get $endpoint _pin_id] ne "" && [llength [dict get $endpoint _pin_point]] == 2}
            lappend paths [dict get $endpoint hierarchy_path]
        }
        if {[llength [lsort -unique $paths]] > 1} {incr cross}
        incr tested
    }
    assert {$tested > 0 && $cross > 0}
    puts "PASS: native occurrence snapshot; $tested networks traced, $cross across hierarchy; actual IDs and pin coordinates available"
    $s -delete; DboTclHelper_sDeleteSession $session
    set f [open $fixture rb]; set after [zlib crc32 [read $f]]; close $f
    assert {$before == $after}
    puts "PASS: isolated sample bytes unchanged; no Capture process, DRC or design write"
} on error {msg opts} {puts stderr [dict get $opts -errorinfo]; exit 1}
