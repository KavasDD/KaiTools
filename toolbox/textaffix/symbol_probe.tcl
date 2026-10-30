# SPDX-License-Identifier: GPL-3.0-only
# Development probe: Capture can forward command-line scripts into an existing
# process. Open only this disposable sample; never edit or close user designs.
set ::xkSymbolDir D:/selfsoftware/toolbox/textaffix/test-output/symbols
file mkdir $::xkSymbolDir
proc xkSymbolPump {} {
    set job $::xkSymbolDir/job.tcl
    if {[file exists $job]} {
        file rename -force $job $::xkSymbolDir/running.tcl
        set ::xkSymbolLog [open $::xkSymbolDir/job.log w]
        fconfigure $::xkSymbolLog -encoding utf-8 -buffering line
        if {[catch {source -encoding utf-8 $::xkSymbolDir/running.tcl} msg opts]} {
            puts $::xkSymbolLog [dict get $opts -errorinfo]
        }
        puts $::xkSymbolLog DONE
        close $::xkSymbolLog
        file delete $::xkSymbolDir/running.tcl
    }
    after 250 xkSymbolPump
}
set f [open $::xkSymbolDir/probe.log w]
fconfigure $f -encoding utf-8 -buffering line
try {
    source D:/selfsoftware/autoload/textaffixMenu.tcl
    file copy -force C:/orcad/Cadence/SPB_17.4/tools/capture/samples/PCB-Layout/FullAdder/FULLADD.DSN $::xkSymbolDir/symbols.dsn
    set p [open $::xkSymbolDir/symbols.opj w]
    puts $p {(ExpressProject "" (ProjectVersion "19981106") (ProjectType "PCB") (Folder "Design Resources" (Folder "Library") (File ".\symbols.dsn" (Type "Schematic Design")) (RUN_Online_Rules "FALSE")) (Folder "Outputs") (Folder "Referenced Projects"))}
    close $p
    Open $::xkSymbolDir/symbols.opj
    OPage FULLADD FULLADD {}
    foreach v [lsort [info globals DboBaseObject_*]] {puts $f [list CONST $v [set ::$v]]}
    set page [GetActivePage]
    foreach m {NewOffPageConnectorsIter NewGlobalsIter NewPortsIter NewOffPageConnector NewGlobal NewPort} {
        catch {$page $m} r
        puts $f [list API $m $r]
    }
    foreach pattern {*OffPage* *NewPort* *NewGlobal*} {puts $f [list COMMANDS $pattern [info commands $pattern]]}
    foreach spec {
        {NewOffPageConnectorsIter NextOffPageConnector delete_DboPageOffPageConnectorsIter 1}
        {NewGlobalsIter NextGlobal delete_DboPageGlobalsIter 0}
        {NewPortsIter NextPort delete_DboPagePortsIter 1}
    } {
        lassign $spec make next del all
        set args {}; if {$all} {lappend args $::IterDefs_ALL}
        foreach obj [::xiaokai::textaffix::each $page $make $next $del {*}$args] {
            puts $f [list SYMBOL $make $obj [$obj GetObjectType] [::xiaokai::textaffix::readString $obj GetName]]
            set s [DboState]
            set it [$obj NewDisplayPropsIter $s]
            for {set dp [$it NextProp $s]} {$dp ne "NULL"} {set dp [$it NextProp $s]} {
                puts $f [list DISPLAY $dp [::xiaokai::textaffix::readString $dp GetName] [$dp GetOwner]]
            }
            delete_DboDisplayPropsIter $it
            $s -delete
        }
    }
    puts $f PASS
} on error {msg opts} {puts $f [dict get $opts -errorinfo]} finally {close $f}
after 250 xkSymbolPump
