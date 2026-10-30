# SPDX-License-Identifier: GPL-3.0-only
# Run only against the disposable FULLADD sample opened by test-output/pump.tcl.
proc ::xkTextAffixSmoke {} {
    set f $::xkProbeLog
    source D:/selfsoftware/autoload/textaffixMenu.tcl
    ::xiaokai::textaffix::hide
    set s [DboState]
    try {
        set page [GetActivePage]
        set parts [::xiaokai::textaffix::each $page NewPartInstsIter NextPartInst delete_DboPagePartInstsIter]
        set p [lindex $parts end]
        set n [DboTclHelper_sMakeCString Value]; set v [DboTclHelper_sMakeCString 10K]
        ::xiaokai::textaffix::check [$p SetEffectivePropStringValue $n $v]
        DboTclHelper_sDeleteCString $v
        set dp [$p GetDisplayProp $n $s]
        DboTclHelper_sDeleteCString $n
        UnSelectAll; SelectObjectById [::xiaokai::textaffix::id $dp]
        set r [::xiaokai::textaffix::applySelection]
        if {$r != 1} {error "Display prefix failed: $::xiaokai::textaffix::status"}
        set inv [::xiaokai::textaffix::inventory [::xiaokai::textaffix::design] {Value}]
        set sel [::xiaokai::textaffix::selection [GetSelectedObjects]]
        set row [lindex [::xiaokai::textaffix::targets $inv $sel] 0]
        if {[dict get $row value] ne "NC/10K"} {error "Expected NC/10K: $row"}
        puts $f {PASS clicked Value: 10K -> NC/10K}
        if {[::xiaokai::textaffix::applySelection] != 1} {error "Existing prefix was not removed"}
        set inv [::xiaokai::textaffix::inventory [::xiaokai::textaffix::design] {Value}]
        if {[dict get [lindex [::xiaokai::textaffix::targets $inv $sel] 0] value] ne "10K"} {error "Prefix removal mismatch"}
        if {[::xiaokai::textaffix::undo] != 1} {error "Removal undo failed"}
        if {[::xiaokai::textaffix::undo] != 1} {error "Prefix undo failed"}
        puts $f {PASS existing prefix removal and two batch undos}
        set ::xiaokai::textaffix::side after
        set ::xiaokai::textaffix::text /NC
        if {[::xiaokai::textaffix::applySelection] != 1} {error "Suffix failed"}
        set inv [::xiaokai::textaffix::inventory [::xiaokai::textaffix::design] {Value}]
        if {[dict get [lindex [::xiaokai::textaffix::targets $inv $sel] 0] value] ne "10K/NC"} {error "Suffix mismatch"}
        if {[::xiaokai::textaffix::undo] != 1} {error "Suffix undo failed"}
        puts $f {PASS suffix and undo}
        # A direct second operation removes only the matching suffix.
        if {[::xiaokai::textaffix::applySelection] != 1 || [::xiaokai::textaffix::applySelection] != 1} {error "Suffix toggle failed"}
        set inv [::xiaokai::textaffix::inventory [::xiaokai::textaffix::design] {Value}]
        if {[dict get [lindex [::xiaokai::textaffix::targets $inv $sel] 0] value] ne "10K"} {error "Suffix removal mismatch"}
        ::xiaokai::textaffix::undo; ::xiaokai::textaffix::undo
        puts $f {PASS existing suffix removal}
        set ::xiaokai::textaffix::side before
        set ::xiaokai::textaffix::text NC/
        UnSelectAll
        foreach p $parts {SelectObjectById [::xiaokai::textaffix::id $p]}
        set count [::xiaokai::textaffix::applySelection]
        if {$count != [llength $parts]} {error "Box parts failed ($count): $::xiaokai::textaffix::status"}
        if {[::xiaokai::textaffix::undo] != $count} {error "Box undo failed"}
        puts $f [list PASS part-batch $count]
        # Select multiple segments from the same logical network.
        set inv [::xiaokai::textaffix::inventory [::xiaokai::textaffix::design] {Value}]
        set grouped {}
        dict for {wk nk} [dict get $inv wireNets] {dict lappend grouped $nk $wk}
        set selectedNet ""
        dict for {nk wires} $grouped {if {[llength $wires] > 1 && [lindex $nk 0] eq "FULLADD"} {set selectedNet $nk; break}}
        if {$selectedNet eq ""} {error "Fixture has no segmented net"}
        UnSelectAll
        foreach wk [dict get $grouped $selectedNet] {SelectObjectById [lindex $wk 2]}
        set selected [GetSelectedObjects]
        set count [::xiaokai::textaffix::applySelection]
        if {$count <= 0} {error "Net batch failed: $::xiaokai::textaffix::status"}
        set fresh [::xiaokai::textaffix::inventory [::xiaokai::textaffix::design] {Value}]
        set newNet [list [lindex $selectedNet 0] NC/[lindex $selectedNet 1]]
        if {![dict exists $fresh names $newNet]} {error "Network connectivity name did not update: $selectedNet -> $newNet"}
        if {[::xiaokai::textaffix::undo] != $count} {error "Network undo failed: $::xiaokai::textaffix::status"}
        puts $f [list PASS net-segments [llength $selected] label-changes $count]
        # Named port-driven network: addition and removal update connectivity.
        set inv [::xiaokai::textaffix::inventory [::xiaokai::textaffix::design] {Value}]
        dict for {wk nk} [dict get $inv wireNets] {
            if {$nk eq {FULLADD CARRY_IN}} {set wid [lindex $wk 2]; break}
        }
        UnSelectAll; SelectObjectById $wid
        if {[::xiaokai::textaffix::applySelection] != 1} {error "Named network prefix failed"}
        if {[::xiaokai::textaffix::applySelection] != 1} {error "Named network prefix removal failed"}
        set inv [::xiaokai::textaffix::inventory [::xiaokai::textaffix::design] {Value}]
        if {![dict exists $inv names {FULLADD CARRY_IN}]} {error "Named network removal did not restore connectivity name"}
        ::xiaokai::textaffix::undo; ::xiaokai::textaffix::undo
        puts $f {PASS named network add/remove and connectivity}
        # Also exercise creating a label for an automatically named net.
        set inv [::xiaokai::textaffix::inventory [::xiaokai::textaffix::design] {Value}]
        set labelled [dict values [dict get $inv memberNets]]; set seed ""
        dict for {nk r} [dict get $inv seeds] {
            if {[lsearch -exact $labelled $nk] < 0 && [lindex $nk 0] eq "FULLADD"} {set seed $r; break}
        }
        if {$seed eq ""} {error "Fixture has no automatically named net"}
        UnSelectAll; SelectObjectById [lindex [dict get $seed key] 2]
        if {[::xiaokai::textaffix::applySelection] != 1} {error "Create alias failed: $::xiaokai::textaffix::status"}
        if {[::xiaokai::textaffix::undo] != 1} {error "Delete created alias failed: $::xiaokai::textaffix::status"}
        puts $f {PASS automatically named wire: create label and undo}
        ::xiaokai::textaffix::show
        update idletasks
        if {!$::xiaokai::textaffix::active} {error "Opening did not start continuous mode"}
        focus -force .xiaokaiTextAffix.text
        event generate .xiaokaiTextAffix.text <Escape>
        update
        if {$::xiaokai::textaffix::active || [winfo ismapped .xiaokaiTextAffix]} {error "Tk Escape failed to stop and close"}
        puts $f {PASS automatic continuous mode and Escape in tool window}
        puts $f PASS
    } finally {$s -delete}
}
::xkTextAffixSmoke
