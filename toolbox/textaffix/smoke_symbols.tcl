# SPDX-License-Identifier: GPL-3.0-only
# Run only with symbol_probe.tcl's disposable sample active.
proc xkSymbolAssert {condition message} {
    if {![uplevel 1 [list expr $condition]]} {error $message}
}
proc xkSymbolValue {obj} {::xiaokai::textaffix::readString $obj GetName}
proc xkSymbolSelect {objects} {
    UnSelectAll
    foreach obj $objects {SelectObjectById [::xiaokai::textaffix::id $obj]}
    update
}
proc xkSymbolSmoke {} {
    source D:/selfsoftware/autoload/textaffixMenu.tcl
    set f $::xkSymbolLog
    Open D:/selfsoftware/toolbox/textaffix/test-output/symbols/symbols.opj
    OPage FULLADD FULLADD {}
    set d [::xiaokai::textaffix::design]
    set expected D:/selfsoftware/toolbox/textaffix/test-output/symbols/symbols.dsn
    xkSymbolAssert {[string equal -nocase [file normalize [xkSymbolValue $d]] [file normalize $expected]]} {Refusing to modify a non-fixture design}
    set page [GetActivePage]; set s [DboState]; set made {}
    try {
        set c [DboTclHelper_sMakeCString C:/orcad/Cadence/SPB_17.4/tools/capture/library/CAPSYM.OLB]
        set lib [$::DboSession_s_pDboSession GetLib $c $s]
        DboTclHelper_sDeleteCString $c
        # GetLib may make its library editor active; restore the fixture page.
        Open D:/selfsoftware/toolbox/textaffix/test-output/symbols/symbols.opj
        OPage FULLADD FULLADD {}
        update
        foreach spec {
            {NewOffPageConnectorsIter NextOffPageConnector delete_DboPageOffPageConnectorsIter DeleteOffPageConnector}
            {NewPortsIter NextPort delete_DboPagePortsIter DeletePort}
            {NewGlobalsIter NextGlobal delete_DboPageGlobalsIter DeleteGlobal}
        } {
            lassign $spec make next del remove
            foreach obj [::xiaokai::textaffix::each $page $make $next $del] {
                if {[string match *XK_* [xkSymbolValue $obj]]} {
                    ::xiaokai::textaffix::check [$page $remove $obj]
                }
            }
        }
        foreach spec {
            {NewOffPageConnector GetOffPageSymbol OFFPAGELEFT-L XK_LINK 200}
            {NewPort GetPortSymbol PORTLEFT-L XK_PORT 400}
            {NewGlobal GetGlobalSymbol VCC XK_POWER 600}
        } {
            lassign $spec make get symbol name x
            set c [DboTclHelper_sMakeCString $symbol]
            set sym [$lib $get $c $s]
            DboTclHelper_sDeleteCString $c
            xkSymbolAssert {$sym ne "NULL" && [$s OK]} "Missing symbol $symbol"
            set c [DboTclHelper_sMakeCString $name]
            set pt [DboTclHelper_sMakeCPoint $x 200]
            set obj [$page $make $s $c $sym $pt]
            DboTclHelper_sDeleteCString $c
            DboTclHelper_sDeleteCPoint $pt
            xkSymbolAssert {$obj ne "NULL" && [$s OK]} "Cannot create $make"
            lappend made $obj
            puts $f [list FIXTURE $make [$obj GetObjectType] [xkSymbolValue $obj]]
        }
        ::xiaokai::textaffix::check [$page MarkModified]
        DboTclHelper_sEvalPage $page
        ZoomRedraw
        foreach obj $made {
            set original [xkSymbolValue $obj]
            xkSymbolSelect [list $obj]
            xkSymbolAssert {[::xiaokai::textaffix::applySelection] == 1} "Body add failed: $::xiaokai::textaffix::status"
            xkSymbolAssert {[xkSymbolValue $obj] eq "NC/$original"} {Body prefix mismatch}
            xkSymbolAssert {[::xiaokai::textaffix::applySelection] == 1} {Existing prefix removal failed}
            xkSymbolAssert {[xkSymbolValue $obj] eq $original} {Removal mismatch}
            xkSymbolAssert {[::xiaokai::textaffix::undo] == 1} {Removal undo failed}
            xkSymbolAssert {[::xiaokai::textaffix::undo] == 1} {Body add undo failed}
            set c [DboTclHelper_sMakeCString Name]
            set dp [$obj GetDisplayProp $c $s]
            DboTclHelper_sDeleteCString $c
            xkSymbolAssert {$dp ne "NULL"} "Missing Name display for $original"
            xkSymbolSelect [list $dp]
            set ::xiaokai::textaffix::side after
            set ::xiaokai::textaffix::text /NC
            xkSymbolAssert {[::xiaokai::textaffix::applySelection] == 1} "Name display suffix failed: $::xiaokai::textaffix::status"
            xkSymbolAssert {[xkSymbolValue $obj] eq "$original/NC"} {Display suffix mismatch}
            xkSymbolAssert {[::xiaokai::textaffix::applySelection] == 1} {Existing suffix removal failed}
            xkSymbolAssert {[xkSymbolValue $obj] eq $original} {Suffix removal mismatch}
            xkSymbolAssert {[::xiaokai::textaffix::undo] == 1 && [::xiaokai::textaffix::undo] == 1} {Suffix undos failed}
            set ::xiaokai::textaffix::side before
            set ::xiaokai::textaffix::text NC/
            puts $f [list PASS symbol-body-and-name [$obj GetObjectType] $original prefix-removal suffix-removal undo]
        }
        xkSymbolSelect $made
        xkSymbolAssert {[::xiaokai::textaffix::applySelection] == 3} {Mixed symbol batch failed}
        xkSymbolAssert {[::xiaokai::textaffix::undo] == 3} {Mixed symbol batch undo failed}
        puts $f {PASS mixed-symbol batch and undo}
        set wiredPort ""
        foreach obj [::xiaokai::textaffix::each $page NewPortsIter NextPort delete_DboPagePortsIter $::IterDefs_ALL] {
            if {[xkSymbolValue $obj] eq "CARRY_IN"} {set wiredPort $obj; break}
        }
        xkSymbolAssert {$wiredPort ne ""} {Missing wired fixture port}
        set inv [::xiaokai::textaffix::inventory $d {}]
        set wire ""
        dict for {nk r} [dict get $inv seeds] {
            if {$nk eq {FULLADD CARRY_IN}} {set wire [dict get $r object]; break}
        }
        xkSymbolAssert {$wire ne ""} {Missing wired fixture network}
        set c [DboTclHelper_sMakeCString Name]
        set dp [$wiredPort GetDisplayProp $c $s]
        DboTclHelper_sDeleteCString $c
        xkSymbolSelect [list $wiredPort $dp $wire]
        xkSymbolAssert {[::xiaokai::textaffix::applySelection] == 1} {Wire + symbol + Name was not deduplicated}
        xkSymbolAssert {[xkSymbolValue $wiredPort] eq "NC/CARRY_IN"} {Wired port rename mismatch}
        xkSymbolAssert {[::xiaokai::textaffix::undo] == 1} {Wired port undo failed}
        puts $f {PASS wired symbol/Name/wire deduplication and undo}
        puts $f PASS
    } finally {
        $s -delete
        ::xiaokai::textaffix::hide
    }
}
# The older suite uses this log variable.
set ::xkProbeLog $::xkSymbolLog
xkSymbolSmoke
