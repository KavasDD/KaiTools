# Separate native database session; never touches the user's Capture process.
fconfigure stdout -encoding utf-8
set root [file dirname [info script]]
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
try {
    load {C:/orcad/Cadence/SPB_17.4/tools/bin/orDb_Dll_Tcl64.dll} DboTclWriteBasic
    source [file join $root .. .. autoload drctoolMenu.tcl]
    set directory [file join $root test-output command-native-[pid]]; file mkdir $directory
    set fixture [file join $directory fulladd.dsn]
    file copy {C:/orcad/Cadence/SPB_17.4/tools/capture/samples/PCB-Layout/FullAdder/FULLADD.DSN} $fixture
    set session [DboTclHelper_sCreateSession]; set s [DboState]
    set path [DboTclHelper_sMakeCString $fixture]
    set design [$session GetDesignAndSchematics $path $s]; DboTclHelper_sDeleteCString $path
    set page [::xiaokai::drc::reviewPage $design FULLADD FULLADD]
    proc ::xiaokai::drc::activeDesign {} {return $::design}
    proc GetActivePage {} {return $::page}
    proc SelectObjectById {id} {set ::selected $id}
    # Bus entries do not implement the graphic-instance offset API. Cover both
    # endpoint directions with real native objects before reading blank space.
    set busBoxes {}
    foreach coords {{60 60 70 70} {110 100 100 110}} {
        lassign $coords x y u v
        set a [DboTclHelper_sMakeCPoint $x $y]; set b [DboTclHelper_sMakeCPoint $u $v]
        try {
            set entry [$page NewBusEntry $s $a $b]
            assert {$entry ne "NULL" && [$s OK]}
        } finally {DboTclHelper_sDeleteCPoint $a; DboTclHelper_sDeleteCPoint $b}
        lappend busBoxes [list [expr {min($x,$u)}] [expr {min($y,$v)}] [expr {max($x,$u)}] [expr {max($y,$v)}]]
    }
    set occupied [::xiaokai::drc::commandObjects $page]
    foreach box $busBoxes {assert {$box in $occupied}}
    set concise [::xiaokai::drc::commandError {Invalid method. Must be one of: GetEntryPoint GetEndPoint}]
    assert {[string length $concise] < 80 && ![string match {*GetEntryPoint*} $concise]}
    assert {[::xiaokai::drc::commandError {网名重复。}] eq {网名重复。}}
    lassign [::xiaokai::drc::commandSpace $page 160 80] sx sy
    foreach box $busBoxes {
        lassign $box l t r b
        assert {!($sx-20 <= $r && $sx+180 >= $l && $sy-20 <= $b && $sy+100 >= $t)}
    }
    set context [::xiaokai::drc::commandContext]
    puts "CONTEXT OK"
    puts [::xiaokai::drc::commandExecute $context [list ACTION 0123456789abcdef0123456789abcdef locate 0 {} {} 0 {}]]
    assert {[info exists ::selected]}
    puts "BOXES: [llength [::xiaokai::drc::commandObjects $page]]"
    set count [$page GetWireCount $s]
    # Native locate/redraw can revise the document; next tool uses fresh context.
    set context [::xiaokai::drc::commandContext]
    set id 0123456789abcdef0123456789abcdef
    set result [::xiaokai::drc::commandExecute $context [list ACTION $id place_net_wires 4 {} {} -1 {}]]
    puts $result
    assert {[$page GetWireCount $s] == $count+4}
    assert {[catch {::xiaokai::drc::commandExecute $context [list ACTION $id place_net_wires 4 {} {} -1 {}]}]}
    set context [::xiaokai::drc::commandContext]
    assert {[catch {::xiaokai::drc::commandExecute $context [list ACTION $id place_net_wires 4 {} {} -1 {}]}]}
    assert {[$page GetWireCount $s] == $count+4}
    set context [::xiaokai::drc::commandContext]
    puts [::xiaokai::drc::commandExecute $context [list ACTION $id place_text 0 {} [::xiaokai::drc::commandEncode 测试提醒] -1 {}]]
    assert {[catch {::xiaokai::drc::commandExecute [::xiaokai::drc::commandContext] [list ACTION $id eval 0 {} {} -1 {}]}]}
    ::xiaokai::drc::reviewCheckStatus [$session MarkAllLibForSave $design]
    ::xiaokai::drc::reviewCheckStatus [$session SaveDesign $design]
    ::xiaokai::drc::reviewCheckStatus [$session RemoveDesign $design]
    set path [DboTclHelper_sMakeCString $fixture]
    set design [$session GetDesignAndSchematics $path $s]; DboTclHelper_sDeleteCString $path
    set page [::xiaokai::drc::reviewPage $design FULLADD FULLADD]
    assert {[$page GetWireCount $s] == $count+4}
    set names {XKA_0123456789ab_1 XKA_0123456789ab_2 XKA_0123456789ab_3 XKA_0123456789ab_4}
    assert {[catch {::xiaokai::drc::commandUnusedAliases $design $names}]}
    set occupied [::xiaokai::drc::commandObjects $page]
    foreach box $busBoxes {assert {$box in $occupied}}
    puts "PASS: native bus entries (both directions, blank placement, save/reopen), concise errors, wire/alias creation, Text, stale request, duplicate names, invalid action"
} on error {message options} {puts stderr [dict get $options -errorinfo]; exit 1}
