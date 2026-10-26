# SPDX-License-Identifier: GPL-3.0-only
source -encoding utf-8 [file join [file dirname [info script]] core.tcl]
source -encoding utf-8 [file join [file dirname [info script]] presentation.tcl]
source -encoding utf-8 [file join [file dirname [info script]] capture.tcl]
source -encoding utf-8 [file join [file dirname [info script]] netlist.tcl]
package require json
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
set ns ::xiaokai::drc
set IterDefs_SCHEMATICS 1
set queues {}; set deleted {}; set released {}
proc DboState {} {return state}
proc state {method args} {if {$method eq "OK"} {return 1}; return}
proc queueNext {name args} {
    set value [lindex [dict get $::queues $name] 0]
    dict set ::queues $name [lrange [dict get $::queues $name] 1 end]
    return $value
}
proc DboViewToDboSchematic {view} {return $view}
foreach name {views rootPages childPages rootMarkers childMarkers} {interp alias {} $name {} queueNext $name}
foreach type {DboLibViewsIter DboSchematicPagesIter DboPageERCsIter} {
    proc delete_$type {it} {lappend ::released $it}
}
proc design {method args} {
    if {$method eq "NewViewsIter"} {return views}
    error "Unexpected design operation: $method"
}
proc rootSch {method args} {return rootPages}
proc childSch {method args} {return childPages}
proc pageCall {page method args} {
    switch $method {
        NewERCsIter {return ${page}Markers}
        DeleteERC {
            assert {[lsearch -exact $::released ${page}Markers] >= 0}
            set marker [lindex $args 0]
            if {$marker eq $::failedMarker} {error "Injected deletion failure"}
            lappend ::deleted $marker
            return state
        }
        default {error "Unexpected page mutation: $method"}
    }
}
interp alias {} root {} pageCall root
interp alias {} child {} pageCall child
proc resetMarkers {} {
    set ::queues [dict create views {rootSch childSch NULL} rootPages {root NULL} childPages {child NULL} rootMarkers {root1 root2 NULL} childMarkers {child1 NULL}]
    set ::deleted {}; set ::released {}; set ::failedMarker ""
}
resetMarkers
assert {[${ns}::deleteMarkers design] == 3}
assert {$deleted eq "root1 root2 child1"}
assert {[llength $released] == 5}
resetMarkers
set failedMarker root1
assert {[catch {${ns}::deleteMarkers design} message]}
assert {$deleted eq "root2 child1"}
assert {[llength $released] == 5}
puts "PASS: root and child ERC cleanup, iterators released before deletion, remaining markers attempted after failure"

# Save only the checked design, before Batch DRC and again after cleanup.
# Opening another project or creating a design copy remains forbidden.
rename ${ns}::deleteMarkers ${ns}::realDeleteMarkers
rename ${ns}::nativePass ${ns}::realNativePass
rename ${ns}::snapshot ${ns}::realSnapshot
rename ${ns}::activeDesign ${ns}::realActiveDesign
rename ${ns}::cstring ${ns}::realCString
rename ${ns}::focusDesign ${ns}::realFocusDesign
proc ${ns}::activeDesign {} {return design}
proc ${ns}::cstring {args} {return $::designPath}
proc ${ns}::focusDesign {design args} {return $design}
proc GetActiveOpjName {} {return D:/live/project.opj}
set tmp [file normalize [file join [file dirname [info script]] test-output lifecycle-[pid]]]
set designPath [file join $tmp {design with spaces} unsaved.dsn]
file mkdir [file dirname $designPath]
set rawConfig [${ns}::configJson [dict create DesignPath $designPath ERCMatrix {IN_PIN {E W}}]]
proc capGetDRCConfigData {} {return $::rawConfig}
proc capSaveDRCConfigData {config} {set ::restoredConfig $config}
foreach command {Open CloseProject SaveDesign} {proc $command {args} {error "Unexpected project or disk operation"}}
rename ${ns}::saveCurrentDesign ${ns}::realSaveCurrentDesign
proc ${ns}::saveCurrentDesign {design} {
    assert {$design eq "design"}
    incr ::saves
    if {$::failSave} {error "Injected save failure"}
    set ::saved 1
}
set saves 0; set failSave 0; set saved 0
proc ${ns}::snapshot {args} {return {contexts {} pins {}}}
rename ${ns}::designRevision ${ns}::realDesignRevision
proc ${ns}::designRevision {design} {return $::revision}
set revision 1
rename ${ns}::nativeNetlist ${ns}::realNativeNetlist
proc ${ns}::nativeNetlist {design directory} {
    incr ::netlistCalls
    assert {$::cleanups == $::passes}
    assert {$::saved}
    if {$::failNetlist} {error "Injected netlist failure"}
    foreach name {pstchip.dat pstxprt.dat pstxnet.dat} {
        set f [open [file join $directory $name] w]; puts $f native; close $f
    }
    return 0
}
proc ${ns}::nativePass {cfg report} {
    assert {$::saved}
    set ::saved 0
    incr ::passes
    lappend ::reportPaths $report
    file mkdir [file dirname $report]
    set f [open $report w]; puts $f "Checking Entire Design: live"; close $f
    if {$::failNative} {error "Injected native failure"}
    return "Checking Entire Design: live\n"
}
proc ${ns}::deleteMarkers {design} {
    set ::saved 0
    incr ::cleanups
    if {$::failCleanup} {error "Injected cleanup failure"}
    return 1
}
set passes 0; set cleanups 0; set failNative 0; set failCleanup 0; set reportPaths {}
set netlistCalls 0
set failNetlist 0
set result [${ns}::run $tmp]
assert {$passes == 1 && $cleanups == 1}
assert {$saves == 3}
assert {$netlistCalls == 1 && [dict get $result netlist ok]}
assert {[llength [lsort -unique $reportPaths]] == 1}
assert {[dict get $result source] eq $designPath}
assert {[dict get $result design] eq "design"}
assert {$restoredConfig eq $rawConfig && $::xiaokai::drc::busy == 0}
assert {![llength [info commands ${ns}::prepareCopy]]}
assert {![llength [glob -nocomplain -directory $tmp snapshot_*]]}
assert {[dict get $result report_path] eq "[file rootname $designPath].drc"}
assert {[llength [glob -nocomplain -directory [file dirname $designPath] *.drc]] == 1}
assert {![llength [glob -nocomplain -directory [dict get $result workdir] *.drc]]}
assert {![file exists [file join [dict get $result workdir] native]]}
set failNative 1
assert {[catch {${ns}::run $tmp} message]}
assert {[string first "Injected native failure" $message] >= 0}
assert {$cleanups == 2 && $restoredConfig eq $rawConfig && $::xiaokai::drc::busy == 0}
set failCleanup 1; set restoredConfig ""
assert {[catch {${ns}::run $tmp} message]}
assert {[string first "Injected cleanup failure" $message] >= 0}
assert {$cleanups == 3 && $restoredConfig eq $rawConfig && $::xiaokai::drc::busy == 0}
set failNative 0; set failCleanup 0; set failNetlist 1
set result [${ns}::run $tmp]
assert {![dict get $result netlist ok] && [dict get $result violations] == 1}
assert {[dict get $result counts netlist_error] == 1 && $::xiaokai::drc::busy == 0}
set failSave 1; set beforePasses $passes; set beforeCleanups $cleanups; set beforeNetlist $netlistCalls
assert {[catch {${ns}::run $tmp} message]}
assert {[string first "Injected save failure" $message] >= 0}
assert {$passes == $beforePasses && $cleanups == $beforeCleanups && $netlistCalls == $beforeNetlist}
assert {$::xiaokai::drc::busy == 0}
puts "PASS: save before DRC and after cleanup, failed save stops checking, one native batch/file, no snapshot, cleanup/config restore"
