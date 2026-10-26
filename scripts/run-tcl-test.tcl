# SPDX-License-Identifier: GPL-3.0-only
# Tcl 8.6: Unicode-safe source and a failing exit status even for tcltest.
encoding system utf-8
package require tcltest
set ::suiteFailed 0
rename ::tcltest::cleanupTests ::tcltest::originalCleanupTests
proc ::tcltest::cleanupTests {args} {
    if {$::tcltest::numTests(Failed) > 0} {set ::suiteFailed 1}
    tailcall ::tcltest::originalCleanupTests {*}$args
}
set suite [lindex $argv 0]
set argv {}; set argc 0
if {[catch {source -encoding utf-8 $suite} message options]} {
    puts stderr [dict get $options -errorinfo]
    exit 1
}
if {$::suiteFailed || $::tcltest::numTests(Failed) > 0} {
    exit 1
}
exit 0
