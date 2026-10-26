# SPDX-License-Identifier: GPL-3.0-only
# Adapter contract tests. Mocks are based on Cadence's supplied 17.4 examples;
# they verify our traversal/cleanup logic, not the installed Capture process.
source [file join [file dirname [info script]] .. .. autoload bomtoolMenu.tcl]
set ::count 0
set ::ptrs {}; set ::states {}; set ::iters {}
proc assert {expression} {
    if {![uplevel 1 [list expr $expression]]} { error "Assertion failed: $expression" }
    incr ::count
}
proc DboTclHelper_sMakeCString {{text ""}} {
    set id str[incr ::serial]; dict set ::ptrs $id $text; return $id
}
proc DboTclHelper_sGetConstCharPtr {ptr} { return [dict get $::ptrs $ptr] }
proc DboTclHelper_sDeleteCString {ptr} { dict unset ::ptrs $ptr }
proc DboState {} {
    set id state[incr ::serial]
    interp alias {} $id {} stateDispatch $id
    dict set ::states $id 1
    return $id
}
proc stateDispatch {id method args} {
    if {$method eq "OK"} { return [dict get $::states $id] }
    if {$method eq "-delete"} { dict unset ::states $id; rename $id {}; return }
    error "Unknown state method $method"
}
proc DboSession {args} {}
proc session {method} { if {$method eq "GetActiveDesign"} { return design }; error $method }
proc design {method args} {
    switch $method {
        GetRootOccurrence { return root }
        GetCISNotStuffedString { return notstuffed }
        default { error $method }
    }
}
proc DboOccurrenceToDboInstOccurrence {id} { return $id }
proc delete_DboOccurrenceChildrenIter {id} { dict unset ::iters $id; rename $id {} }
proc iterDispatch {id method args} {
    if {$method eq "NextOccurrence"} {
        if {$::failNext} { error "Injected iterator failure" }
        set children [dict get $::iters $id]
        # Cadence documents IDS_DBOSTATE_AT_END on normal exhaustion: !OK.
        if {![llength $children]} {
            dict set ::states [lindex $args 0] 0
            incr ::endCount
            return NULL
        }
        dict set ::states [lindex $args 0] 1
        set child [lindex $children 0]; dict set ::iters $id [lrange $children 1 end]; return $child
    }
    error $method
}
proc objectDispatch {id method args} {
    set d [dict get $::objects $id]
    switch $method {
        NewChildrenIter {
            set iter iter[incr ::serial]; dict set ::iters $iter [::bomtool::get $d children]
            interp alias {} $iter {} iterDispatch $iter; return $iter
        }
        IsPrimitive { return [::bomtool::get $d primitive 0] }
        GetReference { dict set ::ptrs [lindex $args 0] [dict get $d ref]; return [DboState] }
        GetPartInst { return [::bomtool::get $d inst $id] }
        IsVariantPropMapEmpty { return [expr {![dict exists $d variant]}] }
        GetVariantProp {
            set key [dict get $::ptrs [lindex $args 0]]
            if {![dict exists $d variant $key]} { return 0 }
            dict set ::ptrs [lindex $args 1] [dict get $d variant $key]; return 1
        }
        GetEffectivePropStringValue {
            set key [dict get $::ptrs [lindex $args 0]]
            if {[::bomtool::get $d fail] eq $key} { error "Injected property failure" }
            dict set ::ptrs [lindex $args 1] [::bomtool::get [::bomtool::get $d props] $key]
            return [DboState]
        }
        default { error "Unknown object method $method" }
    }
}
set ::serial 0
set ::endCount 0
set ::failNext 0
set ::DboSession_s_pDboSession session
set ::IterDefs_INSTS 1
dict set ::ptrs notstuffed {Not Stuffed}
set props [dict create Value 100nF {PCB Footprint} C0402 MATERIAL X7R Dsecription exact-description Description fallback-description EMPTY retained-empty-field]
set ::objects [dict create root [dict create children {block1 block2 u1a u1b}] \
    block1 [dict create children c1] block2 [dict create children c2] \
    c1 [dict create primitive 1 ref C1 props $props variant [dict create Value 100nF/50V]] \
    c2 [dict create primitive 1 ref C2 props $props variant [dict create {Part Number} {Not Stuffed}]] \
    u1a [dict create primitive 1 ref U1 props [dict create Value IC {PCB Footprint} SOIC8]] \
    u1b [dict create primitive 1 ref U1 props [dict create Value IC {PCB Footprint} SOIC8]]]
dict for {id props} $::objects { interp alias {} $id {} objectDispatch $id }
set rows [::bomtool::captureRows]
assert {[llength $rows] == 3}
assert {[dict get [lindex $rows 0] value] eq "100nF/50V"}
assert {[dict get [lindex $rows 0] footprint] eq "C0402"}
assert {[dict get [lindex $rows 1] dnp] eq "YES"}
assert {[llength [::bomtool::ncEvidence [lindex $rows 1]]] == 1}
assert {[string match {*Part Number=Not Stuffed*} [join [::bomtool::ncEvidence [lindex $rows 1]]]]}
assert {[dict get [lindex $rows 0] description] eq "exact-description"}
assert {[dict get [lindex $rows 0] empty] eq "retained-empty-field"}
assert {$::bomtool::nativeHeaders eq {Reference Value {PCB Footprint} Dsecription Option EMPTY MATERIAL}}
assert {$::bomtool::lineItemDefinition eq "\{Reference\}\t\{Value\}\t\{PCB Footprint\}\t\{Dsecription\}\t\{Option\}\t\{EMPTY\}\t\{MATERIAL\}"}
assert {$::endCount == 3}
assert {[dict size $::states] == 0 && [dict size $::iters] == 0 && [dict size $::ptrs] == 1}
# Empty child collections are normal too, and must not abort sibling traversal.
dict set ::objects block1 children {}
set rows [::bomtool::captureRows]
assert {[llength $rows] == 2 && [dict get [lindex $rows 0] ref] eq "C2"}
dict set ::objects block1 children c1
set ::failNext 1
assert {[catch {::bomtool::captureRows} message] && [string match *Injected* $message]}
set ::failNext 0
assert {[dict size $::states] == 0 && [dict size $::iters] == 0 && [dict size $::ptrs] == 1}
dict set ::objects u1b props Value OTHER
set rows [::bomtool::captureRows]
set u [lindex $rows 2]
assert {[llength $rows] == 3 && [dict get $u capture_conflict] eq "Value"}
assert {[string match {*OTHER*} [dict get $u capture_differences]]}
# Conflicts must not abort the other components or silently choose U1's value.
rename ::bomtool::writeWorkbook ::bomtool::realWriteWorkbook
proc ::bomtool::writeWorkbook {path sheets} { set ::capturedSheets $sheets; return $path }
set report [::bomtool::preprocess $rows unused]
assert {[dict get $report groups] == 1 && [dict get $report excluded] == 2}
assert {[dict get $report pending_packages] == 1}
assert {[llength [lindex [lindex $::capturedSheets 4] 2]] == 4}
set warningRows [lindex [lindex $::capturedSheets 2] 2]
assert {[lindex [lindex $warningRows 0] 8] eq "WARN-PACKAGE-CONFLICT"}
assert {[string match {*OTHER*} [lindex [lindex $warningRows 0] 2]]}
dict set ::objects u1b props Value IC
# Auxiliary metadata differences and missing section attributes are recoverable.
dict set ::objects u1a props Dsecription GateA
dict set ::objects u1b props Dsecription GateB
dict set ::objects u1b props MATERIAL B
dict set ::objects u1a props {PCB Footprint} ""
set rows [::bomtool::captureRows]
set u [lindex $rows 2]
assert {[dict get $u capture_conflict] eq "" && [dict get $u footprint] eq "SOIC8"}
set report [::bomtool::preprocess $rows unused]
assert {[dict get $report groups] == 2 && [dict get $report excluded] == 1}
set warningRows [lindex [lindex $::capturedSheets 2] 2]
assert {[lindex [lindex $warningRows 0] 8] eq "WARN-PACKAGE-METADATA"}
assert {[string match {*GateB*} [lindex [lindex $warningRows 0] 2]]}
assert {[lindex [lindex [lindex [lindex $::capturedSheets 0] 2] 1] 2] == 1}
# Mount-state conflicts are critical even when the other section's flag is empty.
dict set ::objects u1b props Option ns
set rows [::bomtool::captureRows]
assert {[dict get [lindex $rows 2] capture_conflict] ne ""}
dict unset ::objects u1b props Option
dict set ::objects u1b variant [dict create {Part Number} {Not Stuffed}]
set rows [::bomtool::captureRows]
assert {[dict get [lindex $rows 2] capture_conflict] ne ""}
assert {[string match {*Part Number=Not Stuffed*} [dict get [lindex $rows 2] capture_differences]]}
dict unset ::objects u1b variant
dict set ::objects u1a props {PCB Footprint} QFN32
set rows [::bomtool::captureRows]
assert {[dict get [lindex $rows 2] capture_conflict] eq "PCB Footprint"}
dict set ::objects u1a props {PCB Footprint} SOIC8
# Blank metadata in the first section also works in reverse traversal order.
dict set ::objects root children {u1b block1 u1a block2}
set rows [::bomtool::captureRows]
set report [::bomtool::preprocess $rows unused]
set raw [lindex [lindex $::capturedSheets 4] 2]
assert {[lmap r $raw {lindex $r 0}] eq {U1 C1 U1 C2}}
assert {[dict get $report groups] == 2}
rename ::bomtool::writeWorkbook {}
rename ::bomtool::realWriteWorkbook ::bomtool::writeWorkbook
dict set ::objects root children {block1 block2 u1a u1b}
dict set ::objects c1 fail {PCB Footprint}
assert {[catch {::bomtool::captureRows} message] && [string match *Injected* $message]}
assert {[dict size $::states] == 0 && [dict size $::iters] == 0 && [dict size $::ptrs] == 1}
dict unset ::objects c1 fail
dict set ::objects c1 ref C?
assert {[catch {::bomtool::captureRows} message] && [string match *unannotated* $message]}
assert {[dict size $::states] == 0 && [dict size $::iters] == 0 && [dict size $::ptrs] == 1}
puts "PASS: $::count Capture adapter contract assertions (Tcl [info patchlevel])"
