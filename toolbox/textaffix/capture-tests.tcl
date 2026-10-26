# SPDX-License-Identifier: GPL-3.0-only
package require tcltest
namespace import ::tcltest::*
source [file join [file dirname [info script]] core.tcl]
source [file join [file dirname [info script]] capture.tcl]

# Capture-shaped fixture includes a wired port and detached symbols. It catches
# regressions in selection ownership, the real DBGLOBAL type and page inventory.
foreach {name value} {
    DISPLAY_PROP 100 PART_INSTANCE 11 PLACED_INSTANCE 13 DRAWN_INSTANCE 12
    WIRE 19 WIRE_SCALAR 20 WIRE_BUS 21 ALIAS 49 OFF_PAGE_CONNECTOR 38
    DBGLOBAL 37 PORT 23
} {set ::DboBaseObject_$name $value}
set ::IterDefs_SCHEMATICS 1
set ::IterDefs_ALL 0
set ::fixture [dict create \
    design [dict create children [dict create NewViewsIter sch]] \
    sch [dict create name MAIN children [dict create NewPagesIter {page page2}]] \
    page [dict create name PAGE1 owner sch children [dict create NewWiresIter wire NewOffPageConnectorsIter off NewGlobalsIter power NewPortsIter {port detached}]] \
    page2 [dict create name PAGE2 owner sch children [dict create NewOffPageConnectorsIter off2]] \
    wire [dict create type 20 id 1 net SIGNAL children [dict create NewPortsIter port]] \
    port [dict create type 23 id 2 name SIGNAL] \
    off [dict create type 38 id 3 name LINK] \
    power [dict create type 37 id 4 name VCC] \
    detached [dict create type 23 id 5 name FREE] \
    off2 [dict create type 38 id 6 name LINK] \
    portText [dict create type 100 id 7 name Name owner port] \
    offText [dict create type 100 id 8 name Name owner off] \
    powerText [dict create type 100 id 9 name Name owner power]]
proc fixtureObject {obj method args} {
    switch $method {
        GetObjectType {return [dict get $::fixture $obj type]}
        GetOwner {return [dict get $::fixture $obj owner]}
        default {error "Unexpected call: $obj $method $args"}
    }
}
foreach obj [dict keys $::fixture] {interp alias {} $obj {} fixtureObject $obj}
proc GetActivePage {} {return page}
proc DboBaseObjectToDboDisplayProp {obj} {return $obj}
proc DboViewToDboSchematic {obj} {return $obj}
namespace eval ::xiaokai::textaffix {
    proc id {obj} {return [dict get $::fixture $obj id]}
    proc readString {obj method args} {
        if {$method eq "GetName"} {return [dict get $::fixture $obj name]}
        error "Unexpected string call: $obj $method"
    }
    proc netName {obj} {return [dict get $::fixture $obj net]}
    proc each {obj make next destroy args} {
        if {[dict exists $::fixture $obj children $make]} {
            return [dict get $::fixture $obj children $make]
        }
        return {}
    }
}
proc selectedNames {objects} {
    set sel [::xiaokai::textaffix::selection $objects]
    set inv [::xiaokai::textaffix::inventory design {} {MAIN PAGE1}]
    set rows [::xiaokai::textaffix::targets $inv $sel]
    set result {}
    foreach row $rows {lappend result [dict get $row value]}
    return [lsort $result]
}
test symbol-bodies {wired and detached symbol bodies are included} -body {
    selectedNames {port off power detached}
} -result {FREE LINK LINK SIGNAL VCC}
test symbol-displays {display properties resolve to symbol names} -body {
    selectedNames {portText offText powerText}
} -result {LINK LINK SIGNAL VCC}
test net-dedup {symbol and wire name selection is applied only once per source} -body {
    set sel [::xiaokai::textaffix::selection {port portText wire}]
    set inv [::xiaokai::textaffix::inventory design {} {MAIN PAGE1}]
    set plan [::xiaokai::textaffix::makePlan [::xiaokai::textaffix::targets $inv $sel] NC/ before 1]
    list [llength $plan] [dict get [lindex $plan 0] after]
} -result {1 NC/SIGNAL}
test detached-undo-inventory {full inventory resolves detached symbols on all pages for undo} -body {
    set inv [::xiaokai::textaffix::inventory design {}]
    list [dict exists $inv rows {MAIN PAGE1 3 name {}}] [dict exists $inv rows {MAIN PAGE2 6 name {}}]
} -result {1 1}
test symbol-scan-off {property-only inventory excludes network symbols} -body {
    dict size [dict get [::xiaokai::textaffix::inventory design {} {MAIN PAGE1} 0] rows]
} -result 0
test network-toggle {network switch disables bodies and displays} -body {
    set ::xiaokai::textaffix::networks 0
    set names [selectedNames {port off power detached portText offText powerText wire}]
    set ::xiaokai::textaffix::networks 1
    set names
} -result {}
cleanupTests
