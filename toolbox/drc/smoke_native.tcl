# SPDX-License-Identifier: GPL-3.0-only
# Development only. smoke.ps1 provides a disposable copy of the official sample.
proc ::xiaokaiDrcSmokeMarkers {design} {
    set st [DboState]; set ids {}
    try {
        set views [$design NewViewsIter $st $::IterDefs_SCHEMATICS]
        try {
            set view [$views NextView $st]
            while {$view ne "NULL"} {
                set sch [DboViewToDboSchematic $view]
                set pages [$sch NewPagesIter $st]
                try {
                    set page [$pages NextPage $st]
                    while {$page ne "NULL"} {
                        set it [$page NewERCsIter $st]
                        try {
                            set erc [$it NextERC $st]
                            while {$erc ne "NULL"} {lappend ids [$erc GetId $st]; set erc [$it NextERC $st]}
                        } finally {delete_DboPageERCsIter $it}
                        set page [$pages NextPage $st]
                    }
                } finally {delete_DboSchematicPagesIter $pages}
                set view [$views NextView $st]
            }
        } finally {delete_DboLibViewsIter $views}
    } finally {$st -delete}
    return [lsort $ids]
}
proc ::xiaokaiDrcSmokeCrc {path} {
    set f [open $path rb]
    try {return [zlib crc32 [read $f]]} finally {close $f}
}
proc ::xiaokaiDrcSmoke {} {
    set scratch $::env(XIAOKAI_DRC_TEST_SCRATCH)
    set f [open [file join $scratch smoke.log] w]
    fconfigure $f -encoding utf-8 -buffering line
    try {
        source [file join $::env(XIAOKAI_DRC_TEST_REPO) autoload drctoolMenu.tcl]
        set source [file join $scratch validation.dsn]
        Open [file rootname $source].opj
        set design [::xiaokai::drc::activeDesign]
        set design [::xiaokai::drc::focusDesign $design validation.dsn [file rootname $source].opj]
        set crc [::xiaokaiDrcSmokeCrc $source]
        package require json
        set before [json::json2dict [capGetDRCConfigData]]
        set clean [::xiaokai::drc::run [file join $scratch clean]]
        set design [dict get $clean design]
        puts $f [list CLEAN $clean]
        if {[dict get $clean violations] != 0} {error "Official sample is not clean"}
        set model [::xiaokai::drc::snapshot $design]
        set paths {}; foreach ctx [dict get $model contexts] {lappend paths [dict get $ctx path]}
        foreach path {/halfadd_A /halfadd_B} {if {$path ni $paths} {error "Missing reused occurrence $path"}}
        foreach schematic {FULLADD HALFADD} {
        set st [DboState]
        try {
            set name [DboTclHelper_sMakeCString $schematic]
            try {set sch [$design GetSchematic $name $st]} finally {DboTclHelper_sDeleteCString $name}
            set pages [$sch NewPagesIter $st]
            try {set page [$pages NextPage $st]} finally {delete_DboSchematicPagesIter $pages}
            set parts [$page NewPartInstsIter $st]
            try {
                set part [$parts NextPartInst $st]
                while {$part ne "NULL" && ![$part IsPrimitive $st]} {set part [$parts NextPartInst $st]}
            } finally {delete_DboPagePartInstsIter $parts}
            if {$part eq "NULL"} {error "No test part"}
            set point [DboTclHelper_sMakeCPoint 1000 1000]
            set status [$part SetLocation $point]
            try {if {![$status OK]} {error "Cannot move test part"}} finally {$status -delete}
        } finally {$st -delete}
        }
        # Seed root/child markers in the disposable test fixture. The public
        # check must remove them and check the unsaved component moves.
        ::xiaokai::drc::focusDesign $design validation.dsn [file rootname $source].opj
        set raw [capGetDRCConfigData]
        set report [file join $scratch sentinel.drc]
        set cfg [::xiaokai::drc::configFor [json::json2dict $raw] single_node_nets $report]
        dict set cfg DRCMarkerForWarnings 1
        try {::xiaokai::drc::nativePass $cfg $report} finally {
            ::xiaokai::drc::focusDesign $design validation.dsn [file rootname $source].opj
            capSaveDRCConfigData $raw
        }
        set markers [::xiaokaiDrcSmokeMarkers $design]
        if {![llength $markers]} {error "Missing sentinel markers"}
        puts $f [list SEEDED $markers]
        set removed [::xiaokai::drc::deleteMarkers $design]
        if {$removed != [llength $markers] || [llength [::xiaokaiDrcSmokeMarkers $design]]} {error "Native marker deletion failed"}
        puts $f [list DELETED $removed]
        ::xiaokai::drc::focusDesign $design validation.dsn [file rootname $source].opj
        set start [clock milliseconds]
        set defect [::xiaokai::drc::run [file join $scratch defect]]
        puts $f [list DURATION_MS [expr {[clock milliseconds]-$start}]]
        puts $f [list DEFECT $defect]
        set design [dict get $defect design]
        if {[llength [::xiaokaiDrcSmokeMarkers $design]]} {error "DRC markers remain after check"}
        puts $f [list NATIVE_SAVED_DESIGN [expr {$crc != [::xiaokaiDrcSmokeCrc $source]}]]
        set st [DboState]
        try {puts $f [list MODIFIED_AFTER_NATIVE [$design IsModified $st]]} finally {$st -delete}
        set nativeFiles [glob -nocomplain -directory [file dirname $source] *.drc]
        set nativeFiles [lsearch -all -inline -not -exact $nativeFiles $report]
        if {[llength $nativeFiles] != 1} {error "Expected exactly one DRC file"}
        puts $f [list NATIVE_REPORT $nativeFiles]
        set childDiagnostic 0
        foreach row [dict get $defect rows] {if {[dict get $row hierarchy_path] in {/halfadd_A /halfadd_B}} {set childDiagnostic 1}}
        if {!$childDiagnostic} {error "Unsaved child edits were not checked"}
        foreach rule {single_node_nets unconnected_pin} {
            if {[dict get $defect counts $rule] < 2} {error "Missing expected diagnostic: $rule"}
        }
        set after [json::json2dict [capGetDRCConfigData]]
        if {$before ne $after} {error "DRC config not restored"}
        if {[llength [info commands ::xiaokai::drc::savedConfigHook]]} {error "Callback not restored"}
        foreach row [dict get $defect rows] {
            if {[dict get $row rule_id] ne "unconnected_pin"} {continue}
            ::xiaokai::drc::locate $row $defect
            if {![llength [GetSelectedObjects]]} {error "Root navigation did not select part"}
            break
        }
        set model [::xiaokai::drc::snapshot $design]
        foreach path {/halfadd_A /halfadd_B} {
            set found 0
            foreach pin [dict get $model pins] {
                if {[dict get $pin hierarchy_path] ne $path || ![dict get $pin is_primitive]} {continue}
                set row [dict create hierarchy_path $path sheet_name [dict get $pin sheet_name] _schematic [dict get $pin schematic] _targets [list $pin]]
                ::xiaokai::drc::locate $row $defect
                set actual /[string trim [::xiaokai::drc::cstring [GetInstanceOccurrence] GetPathName] /]
                if {$actual ne $path || ![llength [GetSelectedObjects]]} {error "Wrong reused occurrence navigation: $path"}
                set found 1; break
            }
            if {!$found} {error "Missing navigation target $path"}
        }
        puts $f [list EXPORT [::xiaokai::drc::writeReports [file join $scratch reports] [dict get $defect rows] [dict get $defect counts] [dict get $defect waived]]]
        # Exercise the error path after a real native pass creates markers.
        rename ::xiaokai::drc::nativePass ::xiaokai::drc::smokeNativePass
        proc ::xiaokai::drc::nativePass {cfg report} {
            dict set cfg DRCMarkerForWarnings 1
            smokeNativePass $cfg $report
            error "Injected failure after native DRC"
        }
        try {
            if {![catch {::xiaokai::drc::run [file join $scratch failure]} msg] || [string first "Injected failure" $msg] < 0} {error "Expected injected failure"}
        } finally {rename ::xiaokai::drc::nativePass {}; rename ::xiaokai::drc::smokeNativePass ::xiaokai::drc::nativePass}
        if {[llength [::xiaokaiDrcSmokeMarkers $design]]} {error "Markers remain after failed check"}
        if {[json::json2dict [capGetDRCConfigData]] ne $before} {error "Settings not restored after failure"}
        puts $f "PASS: single-batch live root/child edits checked, markers removed on success/failure, one DRC file, root/reused navigation, config restored, HTML/CSV"
    } on error {msg opts} {
        puts $f [dict get $opts -errorinfo]
        puts $f FAIL
    } finally {close $f}
}
::xiaokaiDrcSmoke
