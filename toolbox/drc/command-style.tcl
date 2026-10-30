# Infer defaults from native, connected examples. Never learn isolated AI output.
proc ::xiaokai::drc::commandPartOccurrences {design page} {
    set state [DboState];set result {}
    try {
        set root [$design GetRootOccurrence $state]
        if {$root eq "NULL"} {return {}}
        commandCollectOccurrences $root [$page GetId $state] result $state
        return $result
    } finally {$state -delete}
}
proc ::xiaokai::drc::commandCollectOccurrences {parent pageId resultVar state} {
    upvar 1 $resultVar result
    set it [$parent NewChildrenIter $state $::IterDefs_INSTS]
    try {
        for {set child [$it NextOccurrence $state]} {$child ne "NULL"} {set child [$it NextOccurrence $state]} {
            set occ [DboOccurrenceToDboInstOccurrence $child];set part [$occ GetPartInst $state]
            if {[$part GetOwner] ne "NULL" && ($pageId == -1 || [[$part GetOwner] GetId $state] == $pageId)} {dict lappend result [$part GetId $state] [list $occ [cstring $occ GetReferenceDesignator]]}
            if {![$occ IsPrimitive $state]} {
                if {[$occ IsRecursive $state]} {error "分层递归，无法唯一读取目标器件。"}
                commandCollectOccurrences $occ $pageId result $state
            }
        }
    } finally {delete_DboOccurrenceChildrenIter $it}
}
proc ::xiaokai::drc::commandPartValue {part} {
    set key [DboTclHelper_sMakeCString Value];set value [DboTclHelper_sMakeCString]
    try {
        set status [$part GetEffectivePropStringValue $key $value]
        try {if {![$status OK]} {return ""};return [DboTclHelper_sGetConstCharPtr $value]} finally {$status -delete}
    } finally {DboTclHelper_sDeleteCString $key;DboTclHelper_sDeleteCString $value}
}
proc ::xiaokai::drc::commandSetPartValue {context index value} {
    set parts [dict get $context parts]
    if {![string is integer -strict $index] || $index < 0 || $index >= [llength $parts] || [string length $value] < 1 || [string length $value] > 80 || [regexp {[\x00-\x1f]} $value]} {error "器件或Value参数无效。"}
    lassign [lindex $parts $index] id ref
    set state [DboState];set page [dict get $context page];set part NULL
    set it [$page NewPartInstsIter $state]
    try {
        for {set p [$it NextPartInst $state]} {$p ne "NULL"} {set p [$it NextPartInst $state]} {if {[$p GetId $state] == $id} {set part $p;break}}
    } finally {delete_DboPagePartInstsIter $it}
    set key [DboTclHelper_sMakeCString Value];set next [DboTclHelper_sMakeCString $value];set old "";set changed 0
    try {
        if {$part eq "NULL"} {error "目标器件已变化，请重新读取。"}
        if {![$part IsPrimitive $state]} {error "目标是分层模块，不能用器件Value命令修改其图纸引用。"}
        set occurrences [get [commandPartOccurrences [dict get $context design] $page] $id {}]
        if {[llength $occurrences] > 1} {error "该器件位于复用图纸，请先明确分层实例；本次未修改。"}
        set actor $part
        if {[llength $occurrences] == 1} {lassign [lindex $occurrences 0] actor actualRef} else {set actualRef [cstring $part GetReference]}
        if {$actualRef ne $ref} {error "目标位号已变化，请重新读取。"}
        # Restrict to the page instance; variant and occurrence overrides need a separate tool.
        if {![$part IsVariantPropMapEmpty]} {error "目标器件存在变体属性，请在变体编辑器修改。"}
        set old [commandPartValue $actor]
        commandValidateContext $context
        set changed 1
        reviewCheckStatus [$actor SetEffectivePropStringValue $key $next]
        if {[commandPartValue $actor] ne $value || [$part GetId $state] != $id} {error "器件Value写入复查失败。"}
        reviewCheckStatus [$page MarkModified]
    } on error {msg opts} {
        if {$changed} {
            set previous [DboTclHelper_sMakeCString $old]
            try {if {[catch {reviewCheckStatus [$actor SetEffectivePropStringValue $key $previous]} err]} {append msg " 恢复失败：[commandError $err]"}} finally {DboTclHelper_sDeleteCString $previous}
        }
        return -options $opts $msg
    } finally {DboTclHelper_sDeleteCString $key;DboTclHelper_sDeleteCString $next;$state -delete}
    return "已将 $ref 的 Value 从「$old」改为「$value」，并重新读取核对；位号、位置和连接不变。"
}
proc ::xiaokai::drc::commandPageStyle {page} {
    set state [DboState]; set counts {}; set bands {}; set examples 0; set template NULL
    try {
        foreach row [commandWires $page] {
            if {[regexp {^XKA_} [dict get $row name]]} {continue}
            set points [dict get $row points]
            if {[llength $points] != 2 || [lindex $points 0 1] != [lindex $points 1 1]} {continue}
            set wire [dict get $row object]; set it [$wire NewPortInstsIter $state $::IterDefs_ALL]
            try {set connected [expr {[$it NextPortInst $state] ne "NULL"}]} finally {delete_DboWirePortInstsIter $it}
            if {!$connected} {continue}
            set y [lindex $points 0 1]
            foreach x [list [lindex $points 0 0] [lindex $points 1 0]] {dict lappend bands $x $y}
            incr examples
            set ci [$wire NewOffPageConnectorsIter $state]
            try {
                for {set off [$ci NextOffPageConnector $state]} {$off ne "NULL"} {set off [$ci NextOffPageConnector $state]} {
                    if {[cstring [$off GetSymbol $state] GetName] eq "OFFPAGELEFT-L" && [$off GetRotation $state] == 0 && [$off GetMirror $state] == 1} {
                        if {![catch {commandVerifyOffpage $off $wire [commandXY [$off GetOffsetHotSpot $state]] input $state}]} {set template $off}
                    }
                }
            } finally {delete_DboWireOffPageConnectorsIter $ci}
        }
        dict for {x ys} $bands {
            set ys [lsort -integer -unique $ys]
            for {set i 1} {$i < [llength $ys]} {incr i} {
                set d [expr {[lindex $ys $i]-[lindex $ys [expr {$i-1}]]}]
                if {$d >= 10 && $d <= 100 && $d % 10 == 0} {dict incr counts $d}
            }
        }
        set best 40; set votes 0
        dict for {spacing count} $counts {if {$count > $votes} {set best $spacing;set votes $count}}
        # A single difference is insufficient evidence for a page convention.
        if {$votes < 3} {set best 40}
        return [dict create spacing $best votes $votes examples $examples input_template $template]
    } finally {$state -delete}
}
proc ::xiaokai::drc::commandGraphicPoint {off xy} {
    set point [DboTclHelper_sMakeCPoint {*}$xy]
    try {return [commandXY [$off GetOffsetGraphicPoint $point]]} finally {DboTclHelper_sDeleteCPoint $point}
}
proc ::xiaokai::drc::commandVerifyOffpage {off wire point type state} {
    commandCheckOffpageGraphic [$off GetSymbol $state] $state
    set pin [commandXY [$off GetHotSpot $state]]
    set renderedPin [commandGraphicPoint $off $pin]
    set tip [commandGraphicPoint $off {0 10}];set back [commandGraphicPoint $off {10 10}]
    set facing [expr {[lindex $tip 0] > [lindex $back 0] ? "right" : "left"}]
    set desired [expr {$type eq "input" ? "right" : "left"}]
    # Input: wire must touch the arrow tip. Output: wire touches its back.
    set graphicContact [expr {$type eq "input" ? $tip : $back}]
    set actual [$off GetWire $state]
    if {$renderedPin ne $point || [commandXY [$off GetOffsetHotSpot $state]] ne $point || $graphicContact ne $point || [lindex $tip 1] != [lindex $back 1] || $facing ne $desired || $actual eq "NULL" || [$actual GetId $state] != [$wire GetId $state]} {
        error "连接符图形接触点、热点、方向或实际导线不一致，未通过复查。"
    }
    return $facing
}
proc ::xiaokai::drc::commandNewStyledOffpage {context row point type state} {
    set page [dict get $context page];set design [dict get $context design];set off NULL
    if {$type eq "input"} {
        set template [dict get [commandPageStyle $page] input_template]
    } else {set template NULL}
    try {
        if {$template ne "NULL"} {
            set off [$page NewOffPageConnector $template $state]
        } else {
            lassign [commandInputSymbol $design $state [expr {$type eq "input" ? "OFFPAGELEFT-L" : "OFFPAGELEFT-R"}]] symbol hot
            set c [DboTclHelper_sMakeCString [dict get $row name]];set p [DboTclHelper_sMakeCPoint {*}$point]
            try {set off [$page NewOffPageConnector $state $c $symbol $p 0 [expr {$type eq "input" ? 1 : 0}]]} finally {DboTclHelper_sDeleteCString $c;DboTclHelper_sDeleteCPoint $p}
        }
        if {$off eq "NULL" || ![$state OK]} {error "标准连接符创建失败。"}
        set c [DboTclHelper_sMakeCString [dict get $row name]]
        try {reviewCheckStatus [$off SetName $c]} finally {DboTclHelper_sDeleteCString $c}
        lassign [commandXY [$off GetLocation $state]] x y
        lassign [commandXY [$off GetOffsetHotSpot $state]] hx hy
        set p [DboTclHelper_sMakeCPoint [expr {$x+[lindex $point 0]-$hx}] [expr {$y+[lindex $point 1]-$hy}]]
        try {reviewCheckStatus [$off SetLocation $p]} finally {DboTclHelper_sDeleteCPoint $p}
        # These standalone wires already carry a visible native alias. Showing
        # the connector Name as well duplicates the same text on every row.
        # Only change the new connector; never edit the template's properties.
        if {[llength [dict get $row aliases]] == 1} {
            set props [$off NewDisplayPropsIter $state]
            try {
                for {set prop [$props NextProp $state]} {$prop ne "NULL"} {set prop [$props NextProp $state]} {
                    if {[cstring $prop GetName] eq "Name"} {
                        reviewCheckStatus [$prop SetDisplayType 0]
                        if {[$prop GetDisplayType $state] != 0} {error "连接符重复网名隐藏失败。"}
                    }
                }
            } finally {delete_DboDisplayPropsIter $props}
        }
        commandVerifyOffpage $off [dict get $row object] $point $type $state
        return $off
    } on error {msg opts} {
        if {$off ne "NULL"} {catch {commandDeleteOffpage $page $off}}
        return -options $opts $msg
    }
}
proc ::xiaokai::drc::commandAddInputs {context layout} {
    return [commandEnsureOffpages $context $layout input 1]
}
proc ::xiaokai::drc::commandSetOffpageDirection {context layout} {
    return [commandEnsureOffpages $context $layout [dict get $layout signal_type] 0]
}
proc ::xiaokai::drc::commandEnsureOffpages {context layout type allowCreate} {
    set rows [commandTargetRows $context $layout];set page [dict get $context page]
    set state [DboState];set plans {};set staged {};set backups {};set deleted {};set skipped 0;set added 0
    try {
        foreach row $rows {
            commandSimpleWire $row
            lassign [commandBounds [dict get $row points]] x y r b
            set point [list $x $y];set originals {}
            # Use page geometry, not just GetWire's potentially stale association.
            set it [$page NewOffPageConnectorsIter $state]
            try {
                for {set off [$it NextOffPageConnector $state]} {$off ne "NULL"} {set off [$it NextOffPageConnector $state]} {
                    set hot [commandXY [$off GetOffsetHotSpot $state]]
                    set wire [$off GetWire $state]
                    set name [cstring $off GetName];set detached 0
                    if {$name eq [dict get $row name] && $wire eq "NULL" && [lindex $hot 1] == $y && abs([lindex $hot 0]-$x) <= 100} {
                        set matches 0
                        foreach candidate [dict get $context wires] {if {$name in [dict get $candidate names]} {incr matches}}
                        if {$matches == 1} {set detached 1}
                    }
                    if {!$detached && $hot ne $point && ($wire eq "NULL" || [$wire GetId $state] != [dict get $row id])} {continue}
                    if {$name ne [dict get $row name] || [cstring [$off GetSymbol $state] GetName] ni {OFFPAGELEFT-L OFFPAGELEFT-R} || (!$detached && $hot ne $point)} {error "目标导线有不同网名、复杂位置或非标准连接符，未自动修改。"}
                    commandCheckOffpageGraphic [$off GetSymbol $state] $state
                    lappend originals $off
                }
            } finally {delete_DboPageOffPageConnectorsIter $it}
            if {[llength $originals] > 1} {error "同一端点有重复连接符，请先核对。"}
            if {![llength $originals] && !$allowCreate} {error "目标导线没有页间连接符，不能纠正方向。"}
            foreach other [dict get $context wires] {
                if {[dict get $other id] != [dict get $row id] && [commandPointOnRow $other $point]} {error "目标端点与其他导线相交，不能自动添加连接符。"}
            }
            if {[llength $originals] && ![catch {commandVerifyOffpage [lindex $originals 0] [dict get $row object] $point $type $state}]} {incr skipped;continue}
            lappend plans [list $row $point $originals]
        }
        commandValidateContext $context
        foreach plan $plans {
            lassign $plan row point originals
            set next [commandNewStyledOffpage $context $row $point $type $state]
            lappend staged $next
            foreach off $originals {
                set backup [$page NewOffPageConnector $off $state]
                if {$backup eq "NULL" || ![$state OK]} {error "无法备份原连接符，本次未替换。"}
                lappend backups [list $off $backup]
            }
            if {![llength $originals]} {incr added}
        }
        foreach pair $backups {
            set old [lindex $pair 0]
            reviewCheckStatus [commandDeleteOffpage $page $old]
            lappend deleted $old
        }
        foreach next $staged plan $plans {
            lassign $plan row point originals
            commandVerifyOffpage $next [dict get $row object] $point $type $state
        }
        if {[llength $staged]} {reviewCheckStatus [$page MarkModified]}
    } on error {msg opts} {
        foreach next [lreverse $staged] {if {[catch {reviewCheckStatus [commandDeleteOffpage $page $next]} err]} {append msg " 新对象撤回失败：[commandError $err]"}}
        # Backups of deleted originals remain as restored native instances.
        foreach pair $backups {if {[lindex $pair 0] ni $deleted} {catch {commandDeleteOffpage $page [lindex $pair 1]}}}
        return -options $opts $msg
    } finally {$state -delete}
    set state [DboState]
    try {foreach pair $backups {reviewCheckStatus [commandDeleteOffpage $page [lindex $pair 1]]}} finally {$state -delete}
    set repaired [expr {[llength $staged]-$added}]
    set label [expr {$type eq "input" ? "输入型（箭头向右）" : "输出型（箭头向左）"}]
    if {$allowCreate && $repaired == 0} {return "已为 $added 条现有导线添加同网名的输入型页间连接符；已有 $skipped 个正确。已复查图形接触点、热点、方向及实际连接。"}
    return "已新增 $added 个连接符，将 $repaired 个已有连接符调整为$label；已有 $skipped 个正确。已按图纸样式复查图形接触点、热点及实际连接。"
}

# Keep removed native objects alive until Capture rebuilds its schematic-net
# containers. EvalPage can replace wire objects, so it must run only after the
# entire operation (including rollback), never in the middle of a batch.
namespace eval ::xiaokai::drc {variable commandDeletedOffpages {}}
proc ::xiaokai::drc::commandDeleteOffpage {page off} {
    variable commandDeletedOffpages
    $off Increment
    try {
        $off Disconnect
        set status [$page DeleteOffPageConnector $off]
        if {![$status OK]} {$off Decrement;return $status}
        dict lappend commandDeletedOffpages $page $off
        return $status
    } on error {msg opts} {$off Decrement;return -options $opts $msg}
}
proc ::xiaokai::drc::commandFlushDeletedOffpages {page} {
    variable commandDeletedOffpages
    if {![dict exists $commandDeletedOffpages $page]} {return 0}
    # On failure retain references; a later successful rebuild may release them.
    DboTclHelper_sEvalPage $page
    snapshot [activeDesign]
    snapshot [activeDesign]
    set held [dict get $commandDeletedOffpages $page]
    dict unset commandDeletedOffpages $page
    foreach off $held {$off Decrement}
    return 1
}
