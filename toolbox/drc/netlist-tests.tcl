# SPDX-License-Identifier: GPL-3.0-only
source -encoding utf-8 [file join [file dirname [info script]] core.tcl]
source -encoding utf-8 [file join [file dirname [info script]] presentation.tcl]
source -encoding utf-8 [file join [file dirname [info script]] netlist.tcl]
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
set ns ::xiaokai::drc
assert {[${ns}::ignoredDiagnostic {WARNING(ORCAP-1829): Possible pin type conflict U1,O}]}
assert {[${ns}::ignoredDiagnostic {ERROR(ORCAP-999): Pin type conflict}]}
assert {![${ns}::ignoredDiagnostic {WARNING(ORCAP-1608): Net has no driving source N1}]}
set rows [${ns}::netlistRows "INFO(ORCAP-1): Scanning\nWARNING(ORCAP-2): note\nERROR(ORCAP-3): Invalid property for component 'U1'\n  continuation\nERROR(ORCAP-3): Invalid property for component 'U2'\n"]
assert {[llength $rows] == 2}
assert {[dict get [lindex $rows 0] refdes] eq "U1"}
assert {![${ns}::canLocate [lindex $rows 0]]}
assert {[dict size [${ns}::groupRows $rows]] == 1}
set pst [${ns}::netlistRows {#1 ERROR(ORCAP-36002): Property "PCB Footprint" missing from instance U1B: HALFADD, HALFADD (5.50, 2.40).
#2 ERROR(ORCAP-36018): Netlisting cannot complete because of the errors listed above.}]
assert {[llength $pst] == 1}
assert {[dict get [lindex $pst 0] refdes] eq "U1B"}
assert {[dict get [lindex $pst 0] sheet_name] eq "HALFADD"}
assert {[dict get [lindex $pst 0] _diagnostic schematic] eq "HALFADD"}
set option 0
proc GetOptionBool {name} {return $::option}
proc SetOptionBool {name value} {set ::option [expr {$value ? 1 : 0}]}
proc ${ns}::nativeNetlist {design directory} {
    assert {$::option == 1}
    switch $::mode {
        success {
            foreach name {pstchip.dat pstxprt.dat pstxnet.dat} {
                set f [open [file join $directory $name] w]; puts $f native; close $f
            }
            return 0
        }
        fail {error "Injected native netlist failure"}
        diagnostic {
            set f [open [file join $directory netlist.log] w]
            puts $f {ERROR(ORCAP-3): Invalid property for component 'U1'}; close $f
            return 1
        }
        missing {return 0}
    }
}
set tmp [file join [file dirname [info script]] test-output netlist-[pid]]
foreach mode {success fail diagnostic missing} {
    set result [${ns}::netlistCheck design [file join $tmp $mode]]
    assert {$option == 0}
    assert {[dict get $result ok] == ($mode eq "success")}
    if {$mode ne "success"} {assert {[llength [dict get $result rows]] == 1}}
}
puts "PASS: conflict-only ignore, native netlist errors/grouping, success/error/missing-output handling, suppression restored"
set reports [${ns}::writeReports [file join $tmp export] $rows {netlist_error 2} 0]
set f [open [dict get $reports html] r]
fconfigure $f -encoding utf-8
set html [read $f]; close $f
assert {[string first {netlist_error} $html] >= 0}
assert {[dict size $::xiaokai::drc::rules] == 11}
puts "PASS: netlist errors exported with fixed fields, DRC allowlist stays exactly 11"
