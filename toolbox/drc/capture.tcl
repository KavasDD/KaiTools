# SPDX-License-Identifier: GPL-3.0-only
# This adapter runs only inside Capture. All rule decisions are made by native
# Batch DRC, using its occurrence connectivity and the design's ERC matrix.
proc ::xiaokai::drc::cstring {object method {optional 0}} {
    if {$object eq "NULL" || $object eq ""} {error "Capture: $method received a null object"}
    set c [DboTclHelper_sMakeCString]
    try {
        set status [$object $method $c]
        try {if {![$status OK]} {if {$optional} {return ""}; error "Capture $method failed"}} finally {$status -delete}
        return [DboTclHelper_sGetConstCharPtr $c]
    } finally {DboTclHelper_sDeleteCString $c}
}
proc ::xiaokai::drc::activeDesign {} {
    if {![llength [info commands GetActivePMDesign]]} {error "请在 OrCAD Capture 内运行 DRC。"}
    set design [GetActivePMDesign]
    if {($design eq "NULL" || $design eq "") && [info exists ::DboSession_s_pDboSession]} {
        set session $::DboSession_s_pDboSession
        DboSession -this $session
        set design [$session GetActiveDesign]
    }
    if {$design eq "NULL" || $design eq ""} {error "请先打开原理图设计。"}
    return $design
}
proc ::xiaokai::drc::walk {parent contextsName pinsName} {
    upvar 1 $contextsName contexts $pinsName pins
    set s [DboState]; set it NULL
    try {
        # GetSchematic is the containing schematic and is NULL at the root.
        # GetContents is the implemented schematic of this block occurrence.
        set contents [$parent GetContents $s]
        if {$contents eq "NULL" || ![$s OK]} {error "Capture: 无法读取分层图纸内容。"}
        set schematic [DboViewToDboSchematic $contents]
        set path [cstring $parent GetPathName]
        set path /[string trim $path /]
        set sch [cstring $schematic GetName]
        lappend contexts [dict create path $path schematic $sch]
        set it [$parent NewChildrenIter $s $::IterDefs_INSTS]
        if {$it eq "NULL" || ![$s OK]} {error "Capture: 无法读取分层实例。"}
        set child [$it NextOccurrence $s]
        while {$child ne "NULL"} {
            set occ [DboOccurrenceToDboInstOccurrence $child]
            set primitive [$occ IsPrimitive $s]
            if {!$primitive} {
                if {[$occ IsRecursive $s]} {error "Capture: 分层递归引用，无法完成 DRC。"}
                walk $occ contexts pins
            }
            set inst [$occ GetPartInst $s]
            set page [$inst GetOwner]
            set ref [cstring $occ GetReferenceDesignator]
            set pi [$inst NewPinsIter $s]
            try {
                set pin [$pi NextPin $s]
                while {$pin ne "NULL"} {
                    set p [dict create hierarchy_path $path schematic $sch sheet_name [cstring $page GetName] \
                        refdes $ref package_ref [cstring $occ GetReference] instance_ref [cstring $inst GetReference] pin_name [cstring $pin GetPinName] \
                        pin_number [cstring $pin GetPinNumber 1] pin_type [$pin GetPinType $s] \
                        net_name "" local_net "" flat_net "" is_power 0 is_primitive $primitive _part_id [$inst GetId $s]]
                    dict set p _pin_id [$pin GetId $s]
                    set point [$pin GetOffsetHotSpot $s]
                    try {dict set p _pin_point [list [DboTclHelper_sGetCPointX $point] [DboTclHelper_sGetCPointY $point]]} finally {DboTclHelper_sDeleteCPoint $point}
                    if {[info exists ::DboValue_POWER]} {dict set p is_power [expr {[$pin GetPinType $s] == $::DboValue_POWER}]}
                    set po [$occ GetPortOccurrence $pin $s]
                    if {$po ne "NULL"} {
                        set flat [$po GetFlatNet]
                        if {$flat ne "NULL"} {dict set p flat_net $flat; dict set p net_name [cstring $flat GetName]}
                    }
                    set sn [$schematic GetNet $pin $s]
                    if {$sn ne "NULL"} {
                        dict set p local_net [cstring $sn GetName]
                        if {[dict get $p flat_net] eq ""} {
                            set no [$parent GetNetOccurrence $sn $s]
                            if {$no ne "NULL"} {
                                set flat [$no GetFlatNet $s]
                                if {$flat ne "NULL"} {dict set p flat_net $flat; dict set p net_name [cstring $flat GetName]}
                            }
                        }
                    }
                    lappend pins $p
                    set pin [$pi NextPin $s]
                }
            } finally {delete_DboPartInstPinsIter $pi}
            set child [$it NextOccurrence $s]
        }
        # Native iterators set AT_END (not OK) on normal exhaustion.
    } finally {
        if {$it ne "NULL"} {delete_DboOccurrenceChildrenIter $it}
        $s -delete
    }
}
proc ::xiaokai::drc::snapshot {design} {
    set s [DboState]
    try {
        set root [$design GetRootOccurrence $s]
        if {$root eq "NULL" || ![$s OK]} {error "Capture: 无法取得根实例。"}
        set contexts {}; set pins {}; walk $root contexts pins
        return [dict create contexts $contexts pins $pins]
    } finally {$s -delete}
}
proc ::xiaokai::drc::resolveContexts {header contexts} {
    set result {}
    foreach context $contexts {
        set sch [dict get $context schematic]; set path [dict get $context path]
        # Native occurrence heading is "<path without leading /> <schematic>".
        set expected "[string trim $path /] $sch"
        if {[string equal -nocase [string trim $header] [string trim $expected]]} {lappend result $path}
    }
    if {[llength $result]} {return [lsort -unique $result]}
    # Physical checks may refer to a definition once; expand to its occurrences.
    foreach context $contexts {
        if {[string equal -nocase $header [dict get $context schematic]]} {lappend result [dict get $context path]}
    }
    return [lsort -unique $result]
}
proc ::xiaokai::drc::enrich {rule diagnostic model} {
    set base [row $rule $diagnostic]
    set paths [resolveContexts [dict get $diagnostic schematic] [dict get $model contexts]]
    if {![llength $paths]} {set paths [list [get $base hierarchy_path]]}
    set result {}
    foreach path $paths {
        set row $base; dict set row hierarchy_path $path
        foreach context [dict get $model contexts] {
            if {[dict get $context path] eq $path} {dict set row _schematic [dict get $context schematic]; break}
        }
        set matches {}
        foreach pin [dict get $model pins] {
            if {$path ne "" && ![string equal -nocase $path [dict get $pin hierarchy_path]]} {continue}
            if {[get $base sheet_name] ne "" && ![string equal -nocase [get $base sheet_name] [dict get $pin sheet_name]]} {continue}
            set ref [get $base refdes]; set pn [get $base pin_info]
            if {$ref ne "" && ![string equal -nocase $ref [dict get $pin refdes]] && ![string equal -nocase $ref [dict get $pin instance_ref]]} {continue}
            if {$pn ne "" && ![string equal -nocase $pn [dict get $pin pin_name]] && ![string equal -nocase $pn [dict get $pin pin_number]]} {continue}
            set net [get $base net_name]
            if {$net ne "" && ![string equal -nocase $net [dict get $pin net_name]] && ![string equal -nocase $net [get $pin local_net]]} {continue}
            if {$ref eq "" && $net eq ""} {continue}
            lappend matches $pin
        }
        set nets {}; set refs {}; set details {}
        foreach pin $matches {
            lappend nets [dict get $pin net_name]; lappend refs [dict get $pin refdes]
            if {[get $pin pin_number] ne ""} {
                lappend details "[get $pin refdes] · [get $pin pin_number] 脚（[get $pin pin_name]）"
            } else {lappend details "[get $pin refdes] · [get $pin pin_name]"}
        }
        if {[llength $matches]} {
            dict set row net_name [join [lsort -unique $nets] {; }]
            dict set row refdes [join [lsort -unique $refs] {; }]
            dict set row pin_info [join [lsort -unique $details] {; }]
        }
        dict set row _targets $matches
        dict set row _pin_specific [expr {$rule ne "netlist_error" && ([get $base pin_info] ne "" || [llength $matches] == 1)}]
        if {[dict get $row _pin_specific]} {
            set points {}; foreach pin $matches {if {[get $pin _pin_point] ne ""} {lappend points [dict get $pin _pin_point]}}
            set points [lsort -unique $points]
            if {[llength $points] == 1} {dict set row _focus_point [lindex $points 0]}
        }
        # Exemption requires the complete flat net's pin set, not only the
        # matching message pin; hierarchy boundary pins are not primitive pins.
        set netPins {}
        set flats {}; foreach p $matches {if {[get $p flat_net] ne ""} {lappend flats [dict get $p flat_net]}}
        set seen {}
        foreach p [dict get $model pins] {
            if {![get $p is_primitive 1] || [get $p flat_net] eq "" || [lsearch -exact $flats [dict get $p flat_net]] < 0} {continue}
            # Repeated package power pins in multi-section symbols represent
            # one physical pin. Different hierarchy occurrences stay separate.
            set key [list [get $p hierarchy_path] [get $p refdes] [get $p pin_number]]
            if {[get $p is_power 0]} {set key [list [get $p hierarchy_path] [get $p package_ref [get $p refdes]] [get $p pin_number]]}
            if {[dict exists $seen $key]} {continue}
            dict set seen $key 1
            lappend netPins $p
        }
        lappend result [list $row $netPins]
    }
    return $result
}
proc ::xiaokai::drc::supplyConfig {args} {
    variable pendingConfig; variable configCalls
    incr configCalls
    return $pendingConfig
}
proc ::xiaokai::drc::focusDesign {design designFile {project ""}} {
    # SelectPMItem resolves against the active Project Manager tree. Native
    # diagnostics may leave that tree focused on an occurrence or a DRC row.
    set expected [string map {\\ /} [cstring $design GetName]]
    # Batch diagnostics can leave another docked PM active. SelectPMItem alone
    # then searches the wrong project's tree. Activate the owning project by
    # its full path, as required by Capture's native UI command.
    if {[llength [info commands ::ui::PMActivate]]} {
        if {$project eq ""} {set project [file rootname $expected].opj}
        ui::PMActivate $project
    }
    set attempts {}
    foreach name [lsort -unique [list $designFile [string tolower $designFile] [string toupper $designFile]]] {
        catch {SelectPMItem "Design Resources"}
        if {[catch {SelectPMItem ./$name} why]} {lappend attempts "$name: $why"; continue}
        set actual [GetActivePMDesign]
        if {$actual eq "" || $actual eq "NULL"} {continue}
        set path [string map {\\ /} [cstring $actual GetName]]
        lappend attempts "$name: $path"
        if {[string equal -nocase [file normalize $path] [file normalize $expected]]} {return $actual}
    }
    error "Capture: 无法在项目管理器中重新选中设计 $designFile。\n[join $attempts \n]"
}
proc ::xiaokai::drc::deleteMarkers {design} {
    # Visit schematic definitions, not occurrences: reused blocks share pages.
    # Only DboERC objects are removed; No Connect symbols are separate objects.
    set state [DboState]; set removed 0; set failures {}
    try {
        set views [$design NewViewsIter $state $::IterDefs_SCHEMATICS]
        try {
            set view [$views NextView $state]
            while {$view ne "NULL"} {
                set schematic [DboViewToDboSchematic $view]
                set pages [$schematic NewPagesIter $state]
                try {
                    set page [$pages NextPage $state]
                    while {$page ne "NULL"} {
                        set markers {}; set it [$page NewERCsIter $state]
                        try {
                            set marker [$it NextERC $state]
                            while {$marker ne "NULL"} {lappend markers $marker; set marker [$it NextERC $state]}
                        } finally {delete_DboPageERCsIter $it}
                        # Release the iterator before mutating its collection.
                        foreach marker $markers {
                            if {[catch {
                                set status [$page DeleteERC $marker]
                                try {if {![$status OK]} {error "DeleteERC failed"}} finally {$status -delete}
                            } why]} {lappend failures $why} else {incr removed}
                        }
                        set page [$pages NextPage $state]
                    }
                } finally {delete_DboSchematicPagesIter $pages}
                set view [$views NextView $state]
            }
        } finally {delete_DboLibViewsIter $views}
    } finally {$state -delete}
    if {[llength $failures]} {error "DRC 标记未完全清理：[join $failures {; }]"}
    return $removed
}
proc ::xiaokai::drc::saveCurrentDesign {design} {
    # Use Capture's own session writer for this design only. Do not simulate
    # a confirmation, clear modified flags, or save unrelated open projects.
    if {![info exists ::DboSession_s_pDboSession] || $::DboSession_s_pDboSession eq "NULL"} {
        error "无法取得 Capture 会话，未保存设计，已停止检查。"
    }
    set session $::DboSession_s_pDboSession
    DboSession -this $session
    set status [$session MarkAllLibForSave $design]
    try {
        if {![$status OK]} {error "无法准备保存当前设计，已停止检查。"}
    } finally {$status -delete}
    set status [$session SaveDesign $design]
    try {
        if {![$status OK]} {error "当前设计保存失败，已停止检查。请确认文件可写后重试。"}
    } finally {$status -delete}
    set state [DboState]
    try {
        if {[$design IsModified $state]} {error "当前设计仍有未保存的修改，已停止检查。"}
    } finally {$state -delete}
}
proc ::xiaokai::drc::nativePass {config report} {
    variable pendingConfig; variable configCalls
    set pendingConfig [configJson $config]; set configCalls 0
    set hook ::capAutoDRCConfig_InitDRCConfig
    if {![llength [info procs $hook]]} {error "此 Capture 版本未提供原生 Batch DRC 配置入口。"}
    # Never mistake an older report for the new native result.
    if {[file exists $report]} {file delete $report}
    # Synchronous native menu dispatch. Restore its callback even on failure.
    rename $hook ::xiaokai::drc::savedConfigHook
    interp alias {} $hook {} ::xiaokai::drc::supplyConfig
    set restoreSuppress 0; set commandPath ""; set commandFile ""
    try {
        if {[llength [info commands GetOptionBool]] && [llength [info commands SetOptionBool]] &&
            ![catch {GetOptionBool SuppressMsgBoxInTcl} oldSuppress]} {
            SetOptionBool SuppressMsgBoxInTcl TRUE
            set restoreSuppress 1
        }
        # Pipe directives are interpreted by Capture's script reader, not by
        # Tcl's ordinary source/eval. TclScript runs the one-line command in
        # this process and answers only the known DRC log-summary question.
        if {![llength [info commands TclScript]]} {error "当前 Capture 未提供原生对话框自动应答接口。"}
        set commandFile [file tempfile commandPath xiaokai-drc-XXXXXX.tcl]
        puts $commandFile {Menu "PCB::Design Rules Check" | MessageBox "YES" "One or more errors or warnings were encountered."}
        close $commandFile; set commandFile ""
        TclScript $commandPath
        if {$configCalls != 1} {error "Capture 未执行 DRC 配置回调；请激活设计后重试。"}
        if {![file exists $report] || [file size $report] == 0} {error "Capture 未生成本次原生 DRC 报告：$report"}
    } finally {
        try {
            if {$commandFile ne ""} {close $commandFile}
            if {$commandPath ne "" && [file exists $commandPath]} {file delete $commandPath}
        } finally {
            try {
                rename $hook {}
                rename ::xiaokai::drc::savedConfigHook $hook
                unset pendingConfig
            } finally {
                if {$restoreSuppress} {SetOptionBool SuppressMsgBoxInTcl [expr {$oldSuppress ? "TRUE" : "FALSE"}]}
            }
        }
    }
    set f [open $report r]
    try {fconfigure $f -encoding [encoding system]; set text [read $f]} finally {close $f}
    if {![regexp {Checking (?:Schematic|Entire Design):} $text]} {error "原生报告缺少设计检查记录：$report"}
    return $text
}
proc ::xiaokai::drc::checkCurrent {design project parent whitelist rawOriginal} {
    variable rules; variable busy
    if {$busy} {error "DRC 正在运行。"}
    package require json
    foreach entry $whitelist {
        # Validate selectors before invoking Capture, even when no diagnostics.
        if {![dict size $entry]} {error "Empty power whitelist selector"}
        dict for {k v} $entry {if {$k ni {hierarchy_path sheet_name refdes net_name pin_name pin_number}} {error "Invalid whitelist selector: $k"}}
    }
    set busy 1
    set nativeStarted 0
    set designFile [file tail [string map {\\ /} [cstring $design GetName]]]
    set outdir [file normalize [file join $parent drc_[clock format [clock seconds] -format %Y%m%d_%H%M%S]_[clock clicks]]]
    try {
        set original [json::json2dict $rawOriginal]
        set designPath [file normalize [string map {\\ /} [dict get $original DesignPath]]]
        set designFile [file tail $designPath]
        set report [file rootname $designPath].drc
        file mkdir $outdir
        set rows {}; set counts {}; set waived 0
        set cfg [batchConfig $original $report]
        set nativeStarted 1
        set text [nativePass $cfg $report]
        # One native elaboration, one metadata traversal, one result pass.
        set model [snapshot $design]
        dict for {id spec} $rules {dict set counts $id 0}
        foreach diagnostic [diagnostics $text] {
            if {[ignoredDiagnostic [dict get $diagnostic message]]} {continue}
            set id [get $diagnostic rule_id]
            foreach pair [enrich $id $diagnostic $model] {
                lassign $pair row pins
                if {[exempt $row $pins $whitelist]} {incr waived; continue}
                lappend rows $row; dict incr counts $id
            }
        }
        return [dict create rows $rows counts $counts waived $waived violations [llength $rows] workdir $outdir report_path $report _model $model]
    } on error {msg options} {
        file mkdir $outdir
        set f [open [file join $outdir FAILED.txt] w]
        try {fconfigure $f -encoding utf-8; puts $f [dict get $options -errorinfo]} finally {close $f}
        return -options $options "$msg\n诊断目录：$outdir"
    } finally {
        try {
            # Native Batch DRC saves its dialog settings. Restore all original
            # flags, ERC matrix, ignore list and report path after the run.
            try {
                if {$nativeStarted} {
                    deleteMarkers $design
                    # Marker deletion changes the live design. Persist that
                    # cleanup before PST so it never needs a save confirmation.
                    saveCurrentDesign $design
                }
            } finally {
                # Native view traversal/diagnostic activation can change PM
                # context. Restore settings only on this run's owning project.
                focusDesign $design $designFile $project
                capSaveDRCConfigData $rawOriginal
            }
        } finally {set busy 0}
    }
}
proc ::xiaokai::drc::run {{parent ""} {whitelist {}}} {
    variable busy
    if {$busy} {error "检查正在运行。"}
    set design [activeDesign]
    set source [string map {\\ /} [cstring $design GetName]]
    set project [GetActiveOpjName]
    set design [focusDesign $design [file tail $source] $project]
    package require json
    set rawConfig [capGetDRCConfigData]
    set config [json::json2dict $rawConfig]
    set configured [string map {\\ /} [dict get $config DesignPath]]
    if {![string equal -nocase [file normalize $configured] [file normalize $source]]} {error "请先在项目管理器中选中当前设计，再点击检查。"}
    if {$parent eq ""} {
        if {[info exists ::env(TEMP)]} {set parent $::env(TEMP)} else {set parent [pwd]}
        set parent [file join $parent xiaokai-drc]
    }
    # Running a check explicitly includes saving the current design. Save via
    # the native writer before Batch DRC, then persist marker cleanup as well.
    saveCurrentDesign $design
    set result [checkCurrent $design $project $parent $whitelist $rawConfig]
    # Netlist failures must retain completed DRC results.
    set busy 1
    try {
        if {[llength [info commands ::xiaokai::drc::netlistProgress]]} {netlistProgress}
        set netlist [netlistCheck $design [dict get $result workdir]]
        set netRows {}
        foreach row [dict get $netlist rows] {
            if {[get $row sheet_name] ne "" && [dict exists $row _diagnostic]} {
                set candidates [enrich netlist_error [dict get $row _diagnostic] [dict get $result _model]]
                set matched 0
                foreach pair $candidates {if {[llength [get [lindex $pair 0] _targets]]} {set matched 1; break}}
                foreach pair $candidates {
                    set resolved [lindex $pair 0]
                    # PST uses occurrence refdes. A matching occurrence excludes
                    # same-definition instances with a different reference.
                    if {$matched && ![llength [get $resolved _targets]]} {continue}
                    # A component-property error does not implicate every pin
                    # or net on the part; retain targets solely for navigation.
                    dict set resolved pin_info [get $row pin_info]
                    dict set resolved net_name [get $row net_name]
                    # Native instance labels are parsed by the PST adapter.
                    if {[get $resolved refdes] eq ""} {dict set resolved refdes [get $row refdes]}
                    lappend netRows $resolved
                }
            } else {lappend netRows $row}
        }
        dict set netlist rows $netRows
        dict set result netlist $netlist
        dict set result counts netlist_error [llength [dict get $netlist rows]]
        foreach row [dict get $netlist rows] {dict lappend result rows $row}
        dict set result violations [llength [dict get $result rows]]
    } finally {set busy 0}
    # PST can update native cached properties and mark the design modified.
    # Save those updates too, then record the final revision for navigation.
    saveCurrentDesign $design
    dict unset result _model
    dict set result source $source
    dict set result source_time ""
    dict set result source_size ""
    if {[file isfile $source]} {
        dict set result source_time [file mtime $source]
        dict set result source_size [file size $source]
    }
    dict set result design $design
    dict set result project $project
    dict set result diagnostics [llength [dict get $result rows]]
    dict set result rows [relatedRows [dict get $result rows]]
    dict set result violations [llength [dict get $result rows]]
    dict set result revision [designRevision $design]
    return $result
}
proc ::xiaokai::drc::designRevision {design} {
    # Read only page transaction counters; no connectivity elaboration or pin
    # traversal on the UI timer. Definitions shared by instances are read once.
    set s [DboState]
    try {
        # Opening a page after a save can set IsModified without changing the
        # design. Actual edits advance the page transaction versions below.
        set stamp [list [$design GetTransactionCount] [$design GetModifyTime $s]]
        set views [$design NewViewsIter $s $::IterDefs_SCHEMATICS]
        try {
            set view [$views NextView $s]
            while {$view ne "NULL"} {
                set sch [DboViewToDboSchematic $view]
                set pages [$sch NewPagesIter $s]
                try {
                    set page [$pages NextPage $s]
                    while {$page ne "NULL"} {
                        lappend stamp [list $page [$page GetTransactionCount] [$page GetLastTransactionNumber] [$page GetModifyTime $s] [$page GetPartInstCount $s] [$page GetWireCount $s]]
                        set page [$pages NextPage $s]
                    }
                } finally {delete_DboSchematicPagesIter $pages}
                set view [$views NextView $s]
            }
        } finally {delete_DboLibViewsIter $views}
    } finally {$s -delete}
    return $stamp
}
proc ::xiaokai::drc::resultState {result} {
    if {![dict exists $result source]} {return current}
    set source [dict get $result source]
    if {[get $result source_time] ne "" &&
        (![file isfile $source] || [file mtime $source] != [dict get $result source_time] || [file size $source] != [dict get $result source_size])} {return stale}
    set design [activeDesign]
    if {![string equal -nocase [file normalize [string map {\\ /} [cstring $design GetName]]] [file normalize $source]]} {return other}
    if {[get $result design] ne "" && $design ne [dict get $result design]} {return stale}
    if {[dict exists $result revision] && [designRevision $design] ne [dict get $result revision]} {return stale}
    return current
}
proc drctoolMenuRun {args} {::xiaokai::drc::start; return 1}
proc ::xiaokai::drc::locate {row result} {
    if {[resultState $result] eq "stale"} {error "设计已修改，结果待更新。请重新检查后定位。"}
    set source [dict get $result source]
    if {[get $result source_time] ne ""} {
        if {![file isfile $source]} {error "原设计文件已移动，请重新检查。"}
        if {[file mtime $source] != [dict get $result source_time] || [file size $source] != [dict get $result source_size]} {error "设计保存后已发生变化，请重新检查后定位。"}
    }
    set design [activeDesign]
    set current [string map {\\ /} [cstring $design GetName]]
    if {![string equal -nocase [file normalize $current] [file normalize $source]]} {error "请切回本次检查的设计后再定位。"}
    focusDesign $design [file tail $source] [get $result project]
    # Native DRC and marker cleanup can mark the design modified. Do not
    # reject this state or reset it: unsaved schematic edits must be retained.
    set path [get $row hierarchy_path]
    set sch [get $row _schematic]; set page [get $row sheet_name]
    if {$sch eq "" || $page eq ""} {error "此诊断未提供具体图纸；请查看原生详细信息。"}
    # The third OPage argument selects the precise hierarchical occurrence.
    OPage $sch $page [string trim $path /]
    if {[llength [info commands GetInstanceOccurrence]]} {
        set occ [GetInstanceOccurrence]
        if {$occ ne "NULL" && $occ ne ""} {
            set actual /[string trim [cstring $occ GetPathName] /]
            if {![string equal -nocase $actual $path]} {error "未能切换到指定分层实例 $path，已停止高亮。"}
        }
    }
    UnSelectAll
    set count 0; set selected {}
    foreach target [get $row _targets {}] {
        set id [get $target _part_id]
        if {[get $row _pin_specific 0] && [get $target _pin_id] ne ""} {set id [dict get $target _pin_id]}
        if {$id eq "" || $id in $selected} {continue}
        SelectObjectById $id
        lappend selected $id
        incr count
    }
    if {[get $row _focus_point] ne ""} {
        lassign [dict get $row _focus_point] x y
        set radius [expr {max(20,int([[GetActivePage] GetPhysicalGranularity]*0.45))}]
        ZoomArea [expr {$x-$radius}] [expr {$y-$radius}] [expr {$x+$radius}] [expr {$y+$radius}]
        return
    }
    if {$count} {ZoomSelection; return}
    # All native reports carry user coordinates for graphic diagnostics.
    if {[regexp {\(([-0-9.]+),\s*([-0-9.]+)\)} [get $row message] -> x y]} {
        set active [GetActivePage]
        set scale [$active GetPhysicalGranularity]
        if {$scale <= 0} {error "无法读取图纸坐标比例。"}
        set x [expr {int(round($x * $scale))}]; set y [expr {int(round($y * $scale))}]
        selectWireAt $active $x $y [expr {max(1,int($scale*0.03))}]
        set radius [expr {int($scale * 0.3)}]
        ZoomArea [expr {$x-$radius}] [expr {$y-$radius}] [expr {$x+$radius}] [expr {$y+$radius}]
        return
    }
    error "已打开图纸；原生诊断未提供可定位对象或坐标。"
}
proc ::xiaokai::drc::selectWireAt {page x y tolerance} {
    set s [DboState]; set best ""; set distance [expr {$tolerance*$tolerance}]
    try {
        set wires [$page NewWiresIter $s]
        try {
            set wire [$wires NextWire $s]
            while {$wire ne "NULL"} {
                set last ""
                set n [$wire GetPointCount $s]
                for {set i 0} {$i < $n} {incr i} {
                    set point [$wire GetPoint $i $s]
                    try {set here [list [DboTclHelper_sGetCPointX $point] [DboTclHelper_sGetCPointY $point]]} finally {DboTclHelper_sDeleteCPoint $point}
                    if {$last ne ""} {
                        lassign $last ax ay; lassign $here bx by
                        set dx [expr {$bx-$ax}]; set dy [expr {$by-$ay}]
                        set length [expr {$dx*$dx+$dy*$dy}]
                        set t [expr {$length ? max(0.0,min(1.0,(($x-$ax)*$dx+($y-$ay)*$dy)/double($length))) : 0}]
                        set d [expr {pow($x-$ax-$t*$dx,2)+pow($y-$ay-$t*$dy,2)}]
                        if {$d <= $distance} {set distance $d; set best [$wire GetId $s]}
                    }
                    set last $here
                }
                set wire [$wires NextWire $s]
            }
        } finally {delete_DboPageWiresIter $wires}
    } finally {$s -delete}
    if {$best ne ""} {SelectObjectById $best}
}
proc drctoolMenuEnabled {args} {return true}
if {[llength [info commands RegisterAction]]} {
    catch {UnregisterAction "xiaokaiDrcRun"}
    RegisterAction "xiaokaiDrcRun" drctoolMenuEnabled "" drctoolMenuRun ""
    catch {AddAccessoryMenu "DRC中文增强版" "检查当前设计和网表、中文归纳、双击定位" "::drctoolMenuRun"}
    puts "Xiaokai DRC $::xiaokai::drc::version loaded; use Alt+K or drctoolMenuRun."
}
