# SPDX-License-Identifier: GPL-3.0-only
package require tcltest
namespace import ::tcltest::*
source [file join [file dirname [info script]] core.tcl]
test literal-before {prefix remains literal Tcl/regex punctuation} -body {
    ::xiaokai::textaffix::appendText 10K {NC/[$x];} before
} -result {NC/[$x];10K}
test suffix {append after existing text} -body {
    ::xiaokai::textaffix::appendText 10K /NC after
} -result 10K/NC
test unicode {Chinese text} -body {
    ::xiaokai::textaffix::appendText 电源 备用/ before
} -result 备用/电源
test repeated-before {existing prefix is removed} -body {
    ::xiaokai::textaffix::appendText NC/10K NC/ before
} -result 10K
test repeated-after {existing suffix is removed} -body {
    ::xiaokai::textaffix::appendText 10K/NC /NC after
} -result 10K
test repeated-allowed {explicitly allow repeats} -body {
    ::xiaokai::textaffix::appendText NC/10K NC/ before 0
} -result NC/NC/10K
test suffix-short {short string is not mistaken for a matching suffix} -body {
    ::xiaokai::textaffix::appendText C NC after
} -result CNC
test dedup {mixed selection modifies each target once} -body {
    set rows [list [dict create key a value 10K] [dict create key a value 10K] [dict create key b value NC/20K]]
    set p [::xiaokai::textaffix::makePlan $rows NC/ before 1]
    list [llength $p] [dict get [lindex $p 0] after] [dict get [lindex $p 1] after]
} -result {2 NC/10K 20K}
test exact-prefix {removing prefix can leave an empty property value} -body {
    ::xiaokai::textaffix::appendText NC/ NC/ before
} -result {}
test exact-suffix {removing suffix can leave an empty property value} -body {
    ::xiaokai::textaffix::appendText /NC /NC after
} -result {}
test remove-only-once {only one boundary occurrence is removed} -body {
    ::xiaokai::textaffix::appendText NC/NC/10K NC/ before
} -result NC/10K
test empty-prefix {reject empty input} -body {
    ::xiaokai::textaffix::appendText 10K {} before
} -returnCodes error -match glob -result *
cleanupTests
