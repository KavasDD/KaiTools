# Real Tk selectors, actual cached JSON parsing; only network/placement are mocked.
package require Tk
wm withdraw .
set root [file dirname [file dirname [file normalize [info script]]]]
source [file join $root autoload lceda2orcadMenu.tcl]
source [file join $root autoload xiaokaiSchematicPlugins.tcl]
set ::checks 0
proc check {expression} {if {![uplevel 1 [list expr $expression]]} {error "Assertion failed: $expression"};incr ::checks}
rename lceda::cacheDir lceda::originalCacheDir
proc lceda::cacheDir {} {return [file join $::root dev testdata units]}
lceda2orcadMenuDialog
check {[xiaokaiSchematicPluginsOpen] == 1}
set w .xiaokaiSchematicPlugins
set tree $w.results.tv
$tree item editing -open 1;$tree item lceda -open 1
$tree selection set lceda_number
xiaokaiSchematicPluginsUpdateSelection
foreach count {1 2 4 8 27} {
    set ::lceda2orcadEntry C9900$count
    set wanted [list "\u81ea\u52a8"]
    if {$count>1} {for {set i 0} {$i<$count} {incr i} {lappend wanted [lceda::sectionSuffix $i]}}
    foreach widget [list .lceda2orcad.unit $w.number.unit] {
        check {[$widget cget -values] eq $wanted}
        uplevel #0 [$widget cget -postcommand]
        check {[$widget cget -values] eq $wanted}
    }
    check {$::lceda2orcadUnit eq "\u81ea\u52a8"}
    if {$count>1} {set ::lceda2orcadUnit [lindex $wanted end];lceda2orcadRefreshUnits 1;check {$::lceda2orcadUnit eq [lindex $wanted end]}}
}
check {[lindex $::lceda2orcadUnitChoices end] eq "AA"}
# Selection must reach the same physical section in Capture's dispatch.
proc capGetMostRecentSchFrameID {} {return frame}
proc DboTclHelper_sGetConstCharPtr {v} {return $v}
namespace eval ui {proc SchematicActivate {frame} {return 1}}
proc PlacePartEx {args} {set ::placedArgs $args}
set ::lcedaXml [file join $root out unit-selector-tests library.xml]
set ::lcedaOlb [file join $root out unit-selector-tests library.olb]
check {[lceda2orcadBuildXml] == 1}
check {[llength $::lcedaUnitsByPackage($::lcedaByLcsc(C99008))] == 8}
check {[llength $::lcedaUnitsByPackage($::lcedaByLcsc(C990027))] == 27}
check {[lceda2orcadPlace $::lcedaByLcsc(C99008) {} {} H] == 1}
check {[lindex $::placedArgs 2] eq "H"}
check {[lceda2orcadPlace $::lcedaByLcsc(C990027) {} {} AA] == 1}
check {[lindex $::placedArgs 2] eq "AA"}
# A freshly downloaded response updates both selectors before placement.
set ::downloads 0
rename lceda::fetch lceda::originalFetch
rename lceda::cachePath lceda::originalCachePath
rename lceda::loadCached lceda::originalLoadCached
proc lceda::cachePath {code} {
    if {$code eq "C990099"} {return [file join $::root out no-such-unit-cache.json]}
    return [lceda::originalCachePath $code]
}
proc lceda::loadCached {code} {
    if {$code eq "C990099"} {set code C99008}
    return [lceda::originalLoadCached $code]
}
proc lceda::fetch {code args} {incr ::downloads;if {$code ne "C990099"} {error "simulated download failure"};return fixture}
set ::lceda2orcadEntry C990099
check {$::downloads==0 && [llength $::lceda2orcadUnitChoices]==1}
uplevel #0 [$w.number.unit cget -postcommand]
check {$::downloads==1 && $::lceda2orcadUnitChoices eq [list "\u81ea\u52a8" A B C D E F G H]}
check {[.lceda2orcad.unit cget -values] eq [$w.number.unit cget -values]}
set ::lceda2orcadEntry C990098
uplevel #0 [.lceda2orcad.unit cget -postcommand]
check {[llength $::lceda2orcadUnitChoices]==1 && $::lceda2orcadUnit eq "\u81ea\u52a8"}
check {[string first "simulated download failure" $::lceda2orcadStatus]>=0}
# Inline success clears the input and old letters as before.
rename lceda2orcadAdd lceda2orcadOriginalAdd
proc lceda2orcadAdd {code unit} {set ::added [list $code $unit];return 1}
set ::lceda2orcadEntry C99008
set ::lceda2orcadUnit H
$w.number.add invoke
check {$::added eq {C99008 H}}
check {$::lceda2orcadEntry eq "" && $::lceda2orcadUnitChoices eq [list "\u81ea\u52a8"]}
check {[.lceda2orcad.unit cget -values] eq [$w.number.unit cget -values]}
# Reopening the inline UI uses current data, not a hardcoded A/B list.
set ::lceda2orcadEntry C99004
destroy $w
xiaokaiSchematicPluginsOpen
check {[$w.number.unit cget -values] eq [list "\u81ea\u52a8" A B C D]}
puts "PASS: $::checks real Tk selector checks; 1/2/4/8/27 sections, both windows, download/failure, H dispatch, reset and reopen"
destroy .
exit 0
