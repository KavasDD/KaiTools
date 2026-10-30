# Non-electrical Capture Text annotations. Automatic notes describe native
# observations or ask for verification; they do not assert design intent.
namespace eval ::xiaokai::drc {
    variable reviewVisible 0
    variable reviewPreview {}
    variable reviewItems {}
    variable reviewConfirmed {}
    variable reviewNote ""
    variable reviewHint "选择具体项，查看依据并定位，确认后加入 Text 预览。"
    variable reviewMutating 0
    variable reviewSelecting 0
    variable reviewWorking 0
}
proc ::xiaokai::drc::reviewShortText {row} {
    switch -- [get $row rule_id] {
        unconnected_pin {return "核对漏接"}
        single_node_nets {return "单点连接"}
        drive_source_pin_conflict {return "核对驱动"}
        default {error "该项仅在列表中核对。"}
    }
}
proc ::xiaokai::drc::reviewPlan {checkedResult} {
    set entries {}; set skipped {}; set seen {}
    foreach row [dict get $checkedResult rows] {
        if {[get $row rule_id] ni {unconnected_pin single_node_nets drive_source_pin_conflict}} {continue}
        set key [reviewKey $row]
        if {$key in $seen} {continue}; lappend seen $key
        if {[catch {
            set candidate [reviewCandidate $row $checkedResult]
            set note [reviewVerifiedNote $row $checkedResult]
            if {$note eq "允许悬空"} {error "手册明确允许此未用输出悬空，不放置漏接 Text。"}
            dict set candidate text [expr {$note eq "" ? [reviewShortText $row] : $note}]
            dict set candidate confirmed 1
            set entry [reviewPlacement $candidate $checkedResult 0 $entries]
        } reason]} {
            lappend skipped [dict create row $row reason $reason]
        } else {lappend entries $entry}
    }
    return [dict create entries $entries skipped $skipped]
}
proc ::xiaokai::drc::reviewVerifiedNote {row checkedResult} {
    variable reviewItems; variable reviewPreview
    if {$reviewPreview ne $checkedResult} {return ""}
    dict for {id item} $reviewItems {
        if {[reviewKey [dict get $item row]] ne [reviewKey $row]} {continue}
        set ai [get $item ai {}]
        if {[get $ai verdict] eq "error" && [get $ai suggested_text] in {输入悬空 电源漏接}} {return [dict get $ai suggested_text]}
        if {[get $ai verdict] eq "allowed" && [get $ai suggested_text] eq "允许悬空"} {return "允许悬空"}
    }
    return ""
}
proc ::xiaokai::drc::reviewKey {row} {
    set ids {}
    foreach target [get $row _targets {}] {
        lappend ids [list [get $target _part_id] [get $target _pin_id] [get $target pin_number]]
    }
    return [list [get $row rule_id] [get $row hierarchy_path] [get $row _schematic] \
        [get $row sheet_name] [get $row message] [lsort -unique $ids]]
}
proc ::xiaokai::drc::reviewKeys {rows} {
    set keys {}; foreach row $rows {lappend keys [reviewKey $row]}
    return [lsort $keys]
}
proc ::xiaokai::drc::reviewConnectivity {design} {
    set graph {}
    foreach pin [dict get [snapshot $design] pins] {
        set entry {}
        foreach field {hierarchy_path schematic sheet_name refdes pin_number pin_name pin_type net_name local_net is_primitive part_number manufacturer footprint no_connect _part_id _pin_id _pin_point} {
            lappend entry [get $pin $field]
        }
        lappend graph $entry
    }
    return [lsort $graph]
}
proc ::xiaokai::drc::reviewCandidate {row checkedResult} {
    # Only connection checks belong in this first annotation workflow.
    if {[get $row rule_id] ni {unconnected_pin single_node_nets drive_source_pin_conflict}} {
        error "首版 Text 标注仅支持引脚未连接、单点网络和无驱动源核查。"
    }
    if {![canLocate $row]} {error "没有明确对象，保留列表核查。"}
    set ids {}; set refs {}; set pinIds {}
    foreach target [get $row _targets {}] {
        if {[get $target _part_id] eq ""} {error "缺少器件 ID，不能生成 Text。"}
        lappend ids [get $target _part_id]; lappend refs [get $target refdes]
        if {[get $target _pin_id] ne ""} {lappend pinIds [get $target _pin_id]}
    }
    if {[llength [lsort -unique $ids]] != 1 || [llength [lsort -unique $refs]] != 1} {
        error "诊断未唯一对应一个器件，请用列表定位核查。"
    }
    if {[get $row rule_id] eq "unconnected_pin" && [llength [lsort -unique $pinIds]] != 1} {
        error "未连接引脚的对应关系不唯一，请用列表核查。"
    }
    # Text belongs to a definition, not an occurrence. Do not annotate reused
    # definitions with a conclusion concerning just one of their occurrences.
    set paths {}
    foreach context [get $checkedResult review_contexts {}] {
        if {[get $context schematic] eq [get $row _schematic]} {lappend paths [get $context path]}
    }
    if {[llength [lsort -unique $paths]] != 1 || [lindex $paths 0] ne [get $row hierarchy_path]} {
        error "子图由多个实例复用或实例关系不明，不能写入共用 Text；请按实例定位。"
    }
    return [dict create row $row key [reviewKey $row] part_id [lindex $ids 0] refdes [lindex $refs 0]]
}
proc ::xiaokai::drc::reviewCheckStatus {status} {
    try {if {![$status OK]} {error "Capture Text 操作失败。"}} finally {$status -delete}
}
proc ::xiaokai::drc::reviewPage {design schematic pageName} {
    set s [DboState]; set name [DboTclHelper_sMakeCString $schematic]
    try {
        set sch [$design GetSchematic $name $s]
        if {$sch eq "NULL" || ![$s OK]} {error "找不到预览中的 schematic。"}
        set pages [$sch NewPagesIter $s]; set found NULL
        try {
            for {set page [$pages NextPage $s]} {$page ne "NULL"} {set page [$pages NextPage $s]} {
                if {[cstring $page GetName] eq $pageName} {
                    if {$found ne "NULL"} {error "图纸名称不唯一。"}
                    set found $page
                }
            }
        } finally {delete_DboSchematicPagesIter $pages}
        if {$found eq "NULL"} {error "找不到预览中的图纸。"}
        return $found
    } finally {DboTclHelper_sDeleteCString $name; $s -delete}
}
proc ::xiaokai::drc::reviewProperty {inst} {
    set name [DboTclHelper_sMakeCString XiaokaiReviewedTextV1]
    set value [DboTclHelper_sMakeCString]
    try {
        set status [$inst GetEffectivePropStringValue $name $value]
        try {if {![$status OK]} {return {}}} finally {$status -delete}
        set metadata [DboTclHelper_sGetConstCharPtr $value]
        if {[catch {dict size $metadata}] || [get $metadata owner] ne "xiaokai-reviewed-text-v1" || \
            [get $metadata token] eq "" || ![dict exists $metadata text]} {return {}}
        return $metadata
    } finally {DboTclHelper_sDeleteCString $name; DboTclHelper_sDeleteCString $value}
}
proc ::xiaokai::drc::reviewText {inst} {
    set graphic [DboGraphicInstanceToDboGraphicCommentTextInst $inst]
    if {$graphic eq "NULL"} {error "目标不是原生 Text。"}
    set definition [$graphic GetDboCommentText]
    if {$definition eq "NULL"} {error "无法读取 Text 定义。"}
    return [cstring $definition GetText]
}
proc ::xiaokai::drc::reviewOwned {design} {
    set s [DboState]; set owned {}
    try {
        set views [$design NewViewsIter $s $::IterDefs_SCHEMATICS]
        try {
            for {set view [$views NextView $s]} {$view ne "NULL"} {set view [$views NextView $s]} {
                set sch [DboViewToDboSchematic $view]; set pages [$sch NewPagesIter $s]
                try {
                    for {set page [$pages NextPage $s]} {$page ne "NULL"} {set page [$pages NextPage $s]} {
                        set it [$page NewCommentGraphicsIter $s]
                        try {
                            for {set inst [$it NextCommentGraphic $s]} {$inst ne "NULL"} {set inst [$it NextCommentGraphic $s]} {
                                if {[$inst GetObjectType] != $::DboBaseObject_GRAPHIC_COMMENTTEXT_INST} {continue}
                                set metadata [reviewProperty $inst]
                                if {![dict size $metadata]} {continue}
                                lappend owned [dict create page $page inst $inst metadata $metadata \
                                    unchanged [expr {[reviewText $inst] eq [dict get $metadata text]}]]
                            }
                        } finally {delete_DboPageCommentGraphicsIter $it}
                    }
                } finally {delete_DboSchematicPagesIter $pages}
            }
        } finally {delete_DboLibViewsIter $views}
    } finally {$s -delete}
    return $owned
}
proc ::xiaokai::drc::reviewRemove {design {token ""}} {
    # Collect and release all iterators before removing any native object.
    set records [reviewOwned $design]; set removed 0; set preserved 0
    foreach record $records {
        if {$token ne "" && [get [dict get $record metadata] token] ne $token} {continue}
        if {![dict get $record unchanged]} {incr preserved; continue}
        reviewCheckStatus [[dict get $record page] DeleteCommentGraphic [dict get $record inst]]
        reviewCheckStatus [[dict get $record page] MarkModified]
        incr removed
    }
    return [dict create removed $removed preserved $preserved]
}
proc ::xiaokai::drc::reviewCreate {entry checkedResult token} {
    set row [dict get $entry row]
    set page [reviewPage [dict get $checkedResult design] [get $row _schematic] [get $row sheet_name]]
    set s [DboState]; set inst NULL
    set location [DboTclHelper_sMakeCPoint [dict get $entry x] [dict get $entry y]]
    lassign [reviewTextSize [dict get $entry text]] width height
    set rect [DboTclHelper_sMakeCRect [dict get $entry x] [dict get $entry y] \
        [expr {[dict get $entry x]+$width}] [expr {[dict get $entry y]+$height}]]
    set font [DboTclHelper_sMakeLOGFONT {Microsoft YaHei} -7 0 0 0 400 0 0 0 134 0 0 0 0]
    set text [DboTclHelper_sMakeCString [dict get $entry text]]
    set name [DboTclHelper_sMakeCString XiaokaiReviewedTextV1]
    set metadata [DboTclHelper_sMakeCString [dict create owner xiaokai-reviewed-text-v1 token $token \
        text [dict get $entry text] key [dict get $entry key]]]
    try {
        set inst [$page NewGraphicCommentTextInst $s $rect $location $text $font 0]
        if {$inst eq "NULL" || ![$s OK]} {error "创建原生 Text 失败。"}
        # Text stores its position on the comment definition; the graphic
        # container remains at (0,0). Both bounds and anchor use page units.
        # Capture's documented palette index 8 is RGB(255, 0, 0).
        # Store the override on this Text instance, leaving global colors alone.
        reviewCheckStatus [$inst SetColor $::DboValue_COLOR8]
        if {[$inst GetColor $s] != $::DboValue_COLOR8} {error "原生 Text 未接受红色设置。"}
        set definition [[DboGraphicInstanceToDboGraphicCommentTextInst $inst] GetDboCommentText]
        set point [$definition GetLocation $s]
        try {
            if {[DboTclHelper_sGetCPointX $point] != [dict get $entry x] || [DboTclHelper_sGetCPointY $point] != [dict get $entry y]} {
                error "原生 Text 未接受预览位置，已停止放置。"
            }
        } finally {DboTclHelper_sDeleteCPoint $point}
        # New Text may not have a rendered cache. Resolve persisted definition
        # bounds through native placement rather than rejecting an empty cache.
        set actual [reviewGraphicRect $inst $s]
        lassign [dict get $entry text_rect] l t r b; lassign $actual x y u v
        if {$x < $l || $y < $t || $u > $r || $v > $b || $x == $u || $y == $v} {
            error "原生 Text 实际边界（$actual）超出预留区域（[dict get $entry text_rect]），已撤回本次 Text。"
        }
        reviewCheckStatus [$inst SetEffectivePropStringValue $name $metadata]
        if {[reviewText $inst] ne [dict get $entry text] || ![dict size [reviewProperty $inst]]} {
            error "Text 内容或所有权校验失败。"
        }
        reviewCheckStatus [$page MarkModified]
    } on error {msg opts} {
        if {$inst ne "NULL"} {
            if {[catch {reviewCheckStatus [$page DeleteCommentGraphic $inst]} rollback]} {
                append msg "\n撤回失败：$rollback"
            }
        }
        return -options $opts $msg
    } finally {
        foreach c [list $text $name $metadata] {DboTclHelper_sDeleteCString $c}
        DboTclHelper_sDeleteCPoint $location
        DboTclHelper_sDeleteCRect $rect
        DboTclHelper_sDeleteLOGFONT $font
        $s -delete
    }
}
proc ::xiaokai::drc::reviewBackup {checkedResult} {
    set source [dict get $checkedResult source]
    if {![file isfile $source]} {error "源 DSN 不存在，不能创建操作前备份。"}
    set directory [file join [dict get $checkedResult workdir] text-backup]
    file mkdir $directory
    set backup [file join $directory [file tail $source]]
    file copy $source $backup
    return $backup
}
proc ::xiaokai::drc::reviewApply {entries checkedResult} {
    variable busy; variable reviewMutating; variable powerWhitelist
    if {$busy || $reviewMutating} {error "检查或 Text 操作正在运行。"}
    if {[resultState $checkedResult] ne "current"} {error "设计或检查结果已变化，请重新点击 Text 开关。"}
    if {![llength $entries]} {error "没有可放置的 Text。"}
    set expectedKeys [reviewKeys [dict get $checkedResult rows]]
    # Validate the whole plan before the first mutation; placement must match
    # the exact planned values, even when there are several notes.
    set offsets {}; set seen {}; set reserved {}
    foreach entry $entries {
        set row [dict get $entry row]; set key [reviewKey $row]
        if {$key ni $expectedKeys || $key in $seen || ![get $entry confirmed 0]} {error "Text 未经本次操作授权或不属于当前检查结果。"}
        lappend seen $key
        if {[string length [get $entry text]] > 160 || [string trim [get $entry text]] eq "" || [regexp {[\r\n]} [get $entry text]]} {error "Text 内容须为 1～160 字的单行文本。"}
        set candidate [reviewCandidate $row $checkedResult]
        dict set candidate text [dict get $entry text]
        set id [dict get $candidate part_id]; set offset [get $offsets $id 0]; dict incr offsets $id
        set actual [reviewPlacement $candidate $checkedResult $offset $reserved]
        foreach field {part_id key x y} {if {[dict get $actual $field] ne [dict get $entry $field]} {error "Text 目标或位置已改变，请重新预览。"}}
        lappend reserved $actual
    }
    foreach owned [reviewOwned [dict get $checkedResult design]] {
        if {[dict get $owned unchanged]} {error "请先关闭上次的指错 Text，再重新检查。"}
    }
    set connectivity [reviewConnectivity [dict get $checkedResult design]]
    set backup [reviewBackup $checkedResult]
    set token "[clock seconds]-[clock clicks]"
    set reviewMutating 1
    try {
        foreach entry $entries {reviewCreate $entry $checkedResult $token}
        set verified [run "" $powerWhitelist]
        if {![string equal -nocase [file normalize [dict get $verified source]] [file normalize [dict get $checkedResult source]]]} {
            error "复查工程与预览工程不同。"
        }
        if {[reviewConnectivity [dict get $verified design]] ne $connectivity} {
            error "器件、引脚、网络或位置在操作期间发生变化，已停止并撤回本次标注。"
        }
        if {[reviewKeys [dict get $verified rows]] ne $expectedKeys} {
            error "Text 操作后的检查结果发生变化，已停止并撤回本次标注。"
        }
        return [dict create result $verified token $token backup $backup count [llength $entries]]
    } on error {msg opts} {
        if {[catch {
            set current [activeDesign]
            if {![string equal -nocase [file normalize [string map {\\ /} [cstring $current GetName]]] \
                [file normalize [dict get $checkedResult source]]]} {error "当前工程已切换，不能在其他工程中执行撤回。"}
            reviewRemove $current $token
            saveCurrentDesign $current
        } rollback]} {append msg "\n撤回未完成：$rollback"}
        append msg "\n操作前备份：$backup"
        return -options $opts $msg
    } finally {set reviewMutating 0}
}
proc ::xiaokai::drc::reviewExpire {checkedResult} {
    variable reviewVisible
    set design [activeDesign]
    if {![string equal -nocase [file normalize [string map {\\ /} [cstring $design GetName]]] \
        [file normalize [dict get $checkedResult source]]]} {return}
    set removed [reviewRemove $design]
    set reviewVisible 0
    return $removed
}
