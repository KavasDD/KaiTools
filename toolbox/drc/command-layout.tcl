# Validated native layout operations; model indexes resolve only within a fresh page.
proc ::xiaokai::drc::commandUnitsPerInch {page} {
    set units [$page GetDocUnitsPerInch]
    if {![string is double -strict $units] || !($units > 0 && $units < Inf)} {error "无法读取图纸物理单位，已停止放置。"}
    return $units
}
proc ::xiaokai::drc::commandXY {point} {
    try {return [list [DboTclHelper_sGetCPointX $point] [DboTclHelper_sGetCPointY $point]]} finally {DboTclHelper_sDeleteCPoint $point}
}
proc ::xiaokai::drc::commandExecute {context fields} {
    set succeeded 0
    try {
        set message [commandExecuteBody $context $fields]
        set succeeded 1
        return $message
    } finally {
        set flushed [commandFlushDeletedOffpages [dict get $context page]]
        if {[commandFlushDeletedParts [dict get $context page]]} {set flushed 1}
        if {$succeeded && !$flushed} {
            catch {DboTclHelper_sEvalPage [dict get $context page]}
        }
        catch {ZoomRedraw}
    }
}
proc ::xiaokai::drc::commandExecuteBody {context fields} {
    variable commandFocus
    set before [dict get $context wires]
    set message [commandExecuteNative $context $fields]
    set action [lindex $fields 2]; set ids {}
    if {$action eq "place_net_wires"} {
        set old [lmap r $before {dict get $r id}]
        foreach row [commandWires [dict get $context page]] {if {[dict get $row id] ni $old} {lappend ids [dict get $row id]}}
        set options [commandLayout $context [lindex $fields 7]]
        if {[dict get $options inputs]} {
            if {[catch {
                set fresh [commandContext]; set indices {}; set index 0
                foreach row [dict get $fresh wires] {if {[dict get $row id] in $ids} {lappend indices $index}; incr index}
                append message "\n[commandAddInputs $fresh [dict create target_indices $indices]]"
            } msg opts]} {
                set state [DboState]
                try {
                    foreach row [commandWires [dict get $context page]] {
                        if {[dict get $row id] ni $ids} {continue}
                        set wire [dict get $row object]
                        if {[catch {reviewCheckStatus [[dict get $context page] DeleteWire $wire]} rollback]} {append msg " 撤回新导线失败：[commandError $rollback]"}
                    }
                } finally {$state -delete}
                return -options $opts $msg
            }
        }
    } elseif {$action eq "rename_net_labels"} {
        package require json
        foreach index [dict get [json::json2dict [aiDecode [lindex $fields 7]]] label_indices] {
            set label [lindex [dict get $context labels] $index]
            lappend ids [dict get $label id] [dict get $label wire_id]
        }
    } elseif {$action in {move_wires rename_wires add_offpage_inputs set_offpage_direction}} {
        set layout [commandLayout $context [lindex $fields 7] 1]
        foreach row [commandTargetRows $context $layout] {lappend ids [dict get $row id]}
    }
    if {[llength $ids]} {set commandFocus [dict create design [dict get $context design] page [dict get $context page] ids $ids]}
    return $message
}
proc ::xiaokai::drc::commandNeedsPick {fields} {
    if {[lindex $fields 2] ni {place_net_wires move_wires copy_parts move_parts}} {return 0}
    set raw [lindex $fields 7]
    if {$raw eq ""} {return 0}
    package require json
    return [expr {[get [json::json2dict [aiDecode $raw]] placement] eq "pick"}]
}
proc ::xiaokai::drc::commandPickEnabled {command args} {
    return [expr {[llength $::xiaokai::drc::commandPick] && $command eq "OnLButtonUp"}]
}
proc ::xiaokai::drc::commandPickEvent {args} {after idle ::xiaokai::drc::commandPickApply}
proc ::xiaokai::drc::commandPickApply {} {
    variable commandPick
    if {![llength $commandPick]} {return}
    set pending $commandPick; set commandPick {}; set id [dict get $pending id]
    if {[catch {
        set context [dict get $pending context]; commandValidateContext $context
        set page [dict get $context page]
        set user [GetLastMouseClickPointOnPage]
        if {[llength $user] != 2} {error "无法读取点击位置，请重新点击。"}
        set xy {}
        foreach value $user {
            if {![string is double -strict $value]} {error "点击坐标无效。"}
            lappend xy [expr {round($value*[$page GetPhysicalGranularity])}]
        }
        set fields [dict get $pending fields]
        package require json
        set layout [json::json2dict [aiDecode [lindex $fields 7]]]
        # _picked is created here from native coordinates, never from model data.
        set x [lindex $xy 0]; set y [lindex $xy 1]
        set raw [aiDecode [lindex $fields 7]]
        set raw "[string range [string trim $raw] 0 end-1],\"_picked\":\[$x,$y\]\}"
        lset fields 7 [commandEncode $raw]
        set message [commandExecute $context $fields]
    } msg]} {set message "未执行：[commandError $msg]"}
    commandReply RESULT $id $message
}
if {[llength [info commands RegisterAction]] && ![info exists ::xiaokai::drc::commandPickRegistered]} {
    RegisterAction _cdnOrSchViewCmdComplete ::xiaokai::drc::commandPickEnabled "" ::xiaokai::drc::commandPickEvent ""
    set ::xiaokai::drc::commandPickRegistered 1
}
proc ::xiaokai::drc::commandWires {page} {
    set s [DboState]; set it [$page NewWiresIter $s]; set rows {}
    try {
        for {set wire [$it NextWire $s]} {$wire ne "NULL"} {set wire [$it NextWire $s]} {
            if {[llength $rows] >= 2000} {error "当前页导线过多，请缩小操作范围。"}
            set points {}; set names {}; set aliases {}
            for {set i 0} {$i < [$wire GetPointCount $s]} {incr i} {lappend points [commandXY [$wire GetPoint $i $s]]}
            set ai [$wire NewAliasesIter $s]
            try {
                for {set a [$ai NextAlias $s]} {$a ne "NULL"} {set a [$ai NextAlias $s]} {
                    set aliasName [cstring $a GetName]
                    lappend names $aliasName; lappend aliases [list $a [commandXY [$a GetLocation $s]] $aliasName [$a GetId $s]]
                }
            } finally {delete_DboWireAliasesIter $ai}
            set connectors {}; set ci [$wire NewOffPageConnectorsIter $s]
            try {
                for {set off [$ci NextOffPageConnector $s]} {$off ne "NULL"} {set off [$ci NextOffPageConnector $s]} {
                    set symbol [$off GetSymbol $s]
                    set offName [cstring $off GetName]
                    if {$offName ne "" && $offName ni $names} {lappend names $offName}
                    lappend connectors [dict create id [$off GetId $s] object $off name $offName symbol [cstring $symbol GetName] rotation [$off GetRotation $s] mirror [$off GetMirror $s] hot [commandXY [$off GetOffsetHotSpot $s]]]
                }
            } finally {delete_DboWireOffPageConnectorsIter $ci}
            # Replacing an offpage invalidates Capture's cached DboNet. Reading
            # GetNetName before the next connectivity rebuild can dereference
            # that deleted net and crash the native DLL. Persisted aliases and
            # connector names are authoritative for the standalone operations.
            if {![llength $names]} {
                set net [cstring $wire GetNetName 1]
                if {$net ne ""} {lappend names $net}
            }
            lappend rows [dict create id [$wire GetId $s] object $wire scalar [expr {[$wire GetObjectType] == $::DboBaseObject_WIRE_SCALAR}] points $points names $names name [lindex $names 0] aliases $aliases connectors $connectors]
        }
    } finally {delete_DboPageWiresIter $it; $s -delete}
    return $rows
}
proc ::xiaokai::drc::commandLayout {context encoded {requireTargets 0}} {
    set style [commandPageStyle [dict get $context page]]
    set defaultMil [expr {int(round([dict get $style spacing]*1000.0/[commandUnitsPerInch [dict get $context page]]))}]
    set data [dict create near_index -1 direction auto spacing_mil $defaultMil clearance_mil $defaultMil target_indices {} placement blank spacing_factor 0 inputs 0 preserve_spacing 0 signal_type input]
    if {$encoded ne ""} {
        if {[string length $encoded] > 12000} {error "放置参数过长。"}
        package require json
        set data [dict merge $data [json::json2dict [aiDecode $encoded]]]
    }
    set rows [dict get $context wires]
    if {[dict get $data signal_type] ni {input output}} {error "连接符方向须为输入或输出。"}
    if {[dict get $data inputs] ni {0 1 true false}} {error "输入连接符参数无效。"}
    foreach key {spacing_mil clearance_mil} {
        set value [dict get $data $key]
        if {![string is integer -strict $value] || $value < 20 || $value > 10000} {error "间距应为20～10000mil。"}
        dict set data [string map {_mil {}} $key] [expr {max(10,int(ceil($value*[commandUnitsPerInch [dict get $context page]]/1000.0/10))*10)}]
    }
    set factor [dict get $data spacing_factor]
    if {![string is double -strict $factor] || ($factor != 0 && ($factor < 0.25 || $factor > 4))} {error "相对间距比例无效。"}
    if {[dict get $data placement] ni {blank pick}} {error "放置方式无效。"}
    if {[dict get $data preserve_spacing] ni {0 1 true false}} {error "间距保持参数无效。"}
    if {$factor != 0 || [dict get $data preserve_spacing]} {
        set ys {}
        foreach index [dict get $data target_indices] {
            if {![string is integer -strict $index] || $index < 0 || $index >= [llength $rows]} {error "目标导线不存在。"}
            lappend ys [lindex [dict get [lindex $rows $index] points] 0 1]
        }
        set ys [lsort -integer -unique $ys]
        if {[llength $ys] < 2} {
            if {$factor != 0} {error "请指定至少两条不同行的导线来调整间距。"}
        } else {
            set base [expr {([lindex $ys end]-[lindex $ys 0])/double([llength $ys]-1)}]
            set multiplier [expr {$factor == 0 ? 1.0 : $factor}]
            dict set data spacing [expr {max(10,int(round($base*$multiplier/10))*10)}]
        }
    }
    dict set data spacing_mil [expr {round([dict get $data spacing]*1000.0/[commandUnitsPerInch [dict get $context page]])}]
    set near [dict get $data near_index]
    if {![string is integer -strict $near] || $near < -1 || $near >= [llength $rows]} {error "参考导线不存在。"}
    if {[dict get $data direction] ni {auto left right above below}} {error "放置方向无效。"}
    set targets [dict get $data target_indices]
    if {$requireTargets && ([llength $targets] < 1 || [llength $targets] > 32 || [llength [lsort -unique $targets]] != [llength $targets])} {error "请明确1～32条目标导线。"}
    foreach index $targets {
        if {![string is integer -strict $index] || $index < 0 || $index >= [llength $rows] || $index == $near} {error "目标导线不存在或与参考对象重复。"}
    }
    return $data
}
proc ::xiaokai::drc::commandBounds {points} {
    set xs {}; set ys {}
    foreach p $points {lappend xs [lindex $p 0]; lappend ys [lindex $p 1]}
    if {![llength $xs]} {error "导线没有可读取的坐标。"}
    return [list [tcl::mathfunc::min {*}$xs] [tcl::mathfunc::min {*}$ys] [tcl::mathfunc::max {*}$xs] [tcl::mathfunc::max {*}$ys]]
}
proc ::xiaokai::drc::commandFits {boxes pw ph x y width height {gap 20}} {
    if {$x < 40 || $y < 40 || $x+$width > $pw-40 || $y+$height > $ph-40} {return 0}
    foreach box $boxes {
        lassign $box l t r b
        if {$x-$gap <= $r && $x+$width+$gap >= $l && $y-$gap <= $b && $y+$height+$gap >= $t} {return 0}
    }
    return 1
}
proc ::xiaokai::drc::commandLayoutSpace {context width height layout {exclude {}} {anchor {}}} {
    set page [dict get $context page]; set near [dict get $layout near_index]
    if {$near >= 0} {set anchor [commandBounds [dict get [lindex [dict get $context wires] $near] points]]}
    set boxes [commandObjects $page $exclude]
    set size [$page GetDocUnits]
    try {set pw [DboTclHelper_sGetCSizeX $size]; set ph [DboTclHelper_sGetCSizeY $size]} finally {DboTclHelper_sDeleteCSize $size}
    set clearance [dict get $layout clearance]
    if {[dict exists $layout _picked]} {
        lassign [dict get $layout _picked] x y
        set x [expr {int(round($x/10.0))*10}]; set y [expr {int(round($y/10.0))*10-15}]
        if {![commandFits $boxes $pw $ph $x $y $width $height 10]} {error "点击位置空间不足或与已有对象重叠，请换个空白位置再试。"}
        return [list $x $y]
    }
    if {$anchor ne ""} {
        lassign $anchor l t r b
        set direction [dict get $layout direction]; set best {}; set score Inf
        # Search all available grid locations and choose the closest to the
        # requested side, rather than falling back to another page corner.
        for {set y 40} {$y+$height <= $ph-40} {incr y 20} {
            for {set x 40} {$x+$width <= $pw-40} {incr x 20} {
                set side {}; set distance Inf
                foreach d {right left below above} {
                    if {$direction ne "auto" && $direction ne $d} {continue}
                    switch $d {
                        right {set ok [expr {$x >= $r+$clearance}]; set cost [expr {abs($x-$r-$clearance)+abs($y-$t+15)}]}
                        left {set ok [expr {$x+$width <= $l-$clearance}]; set cost [expr {abs($l-$clearance-$x-$width)+abs($y-$t+15)}]}
                        below {set ok [expr {$y >= $b+$clearance}]; set cost [expr {abs($y-$b-$clearance)+abs($x-$l)}]}
                        above {set ok [expr {$y+$height <= $t-$clearance}]; set cost [expr {abs($t-$clearance-$y-$height)+abs($x-$l)}]}
                    }
                    if {$ok && $cost < $distance} {set distance $cost; set side $d}
                }
                if {$side eq "" || $distance >= $score} {continue}
                if {[commandFits $boxes $pw $ph $x $y $width $height]} {set best [list $x $y]; set score $distance}
            }
        }
        if {$best ne ""} {return $best}
        error "参考导线旁没有满足方向、间距和避让要求的空白位置。"
    }
    for {set y 60} {$y+$height < $ph-60} {incr y 20} {
        for {set x 60} {$x+$width < $pw-60} {incr x 20} {
            if {[commandFits $boxes $pw $ph $x $y $width $height]} {return [list $x $y]}
        }
    }
    error "当前页没有满足间距要求的空白位置。"
}
proc ::xiaokai::drc::commandLayoutDescription {context layout} {
    set near [dict get $layout near_index]
    if {$near < 0} {return ""}
    set label [dict get [lindex [dict get $context wires] $near] name]
    set side [dict get {auto 旁 right 右侧 left 左侧 above 上方 below 下方} [dict get $layout direction]]
    return "（$label$side，净空至少[dict get $layout clearance_mil]mil）"
}
proc ::xiaokai::drc::commandTargetRows {context layout} {
    set rows {}; foreach index [dict get $layout target_indices] {lappend rows [lindex [dict get $context wires] $index]}
    return $rows
}
proc ::xiaokai::drc::commandPointOnRow {row point} {
    lassign $point px py
    set points [dict get $row points]
    for {set i 1} {$i < [llength $points]} {incr i} {
        lassign [lindex $points [expr {$i-1}]] ax ay
        lassign [lindex $points $i] bx by
        if {($px-$ax)*($by-$ay) == ($py-$ay)*($bx-$ax) && $px >= min($ax,$bx) && $px <= max($ax,$bx) && $py >= min($ay,$by) && $py <= max($ay,$by)} {return 1}
    }
    return 0
}
proc ::xiaokai::drc::commandSimpleWire {row} {
    if {![dict get $row scalar]} {error "此命令只处理普通导线，不处理总线。"}
    set points [dict get $row points]
    if {[llength $points] != 2 || [lindex $points 0 1] != [lindex $points 1 1] || [lindex $points 0 0] == [lindex $points 1 0]} {error "仅支持两端点的水平直导线，请先整理目标导线。"}
    if {[dict get $row name] eq "" || [llength [dict get $row aliases]] != 1} {error "目标导线须具有唯一明确的网络别名。"}
    if {[llength [lsort -unique -nocase [dict get $row names]]] != 1} {error "目标导线存在多个网名，请先核对网络。"}
}
proc ::xiaokai::drc::commandRenameWires {context layout encodedNames} {
    set names [split $encodedNames \n]; set rows [commandTargetRows $context $layout]
    if {[llength $names] != [llength $rows] || [llength [lsort -unique -nocase $names]] != [llength $names]} {error "新网名须与目标导线逐条对应且不能重复。"}
    foreach name $names {if {![regexp {^[A-Za-z_][A-Za-z0-9_+.-]{0,63}$} $name]} {error "网名格式无效。"}}
    set s [DboState]; set changes {}; set done {}; set page [dict get $context page]
    try {
        # Connected/whole-network renaming is a different operation; this
        # operation changes only standalone wires and avoids hidden net splits.
        foreach row $rows {
            commandSimpleWire $row; commandWireFree $row $s 1
            lappend changes [list [lindex [lindex [dict get $row aliases] 0] 0] [dict get $row name]]
            foreach attached [commandWireAttachments $row $s] {lappend changes [list [lindex $attached 0] [dict get $row name]]}
        }
        set oldNames [lmap r $rows {dict get $r name}]
        commandUnusedAliases [dict get $context design] $oldNames [lmap c $changes {lindex $c 0}]
        commandUnusedAliases [dict get $context design] $names [lmap c $changes {lindex $c 0}]
        set pins [dict get [snapshot [dict get $context design]] pins]
        foreach pin $pins {
            foreach name $names {if {[string equal -nocase $name [get $pin net_name]]} {error "新网名 $name 已连接其他器件，本次未改名。"}}
        }
        # A repeated old name elsewhere may be an intentional logical net.
        # Reject rather than silently split that existing net into two names.
        foreach row $rows {
            set matches 0
            foreach other [dict get $context wires] {if {[dict get $row name] in [dict get $other names]} {incr matches}}
            if {$matches != 1} {error "旧网名存在多个导线段，请选择完整网络后处理。"}
            foreach pin $pins {if {[string equal -nocase [dict get $row name] [get $pin net_name]]} {error "旧网名已连接器件，不能仅改这段导线的名称。"}}
        }
        commandValidateContext $context
        set newByOld {}; foreach row $rows name $names {dict set newByOld [dict get $row name] $name}
        foreach change $changes {
            lassign $change alias old
            set name [dict get $newByOld $old]
            lappend done $change
            set c [DboTclHelper_sMakeCString $name]
            try {reviewCheckStatus [$alias SetName $c]} finally {DboTclHelper_sDeleteCString $c}
            if {[cstring $alias GetName] ne $name} {error "改名复查失败。"}
        }
        reviewCheckStatus [$page MarkModified]
    } on error {msg opts} {
        foreach change [lreverse $done] {
            lassign $change alias old
            set c [DboTclHelper_sMakeCString $old]
            try {if {[catch {reviewCheckStatus [$alias SetName $c]} rollback]} {append msg " 撤回失败：[commandError $rollback]"}} finally {DboTclHelper_sDeleteCString $c}
        }
        return -options $opts $msg
    } finally {$s -delete}
    return "已将这 [llength $rows] 条导线依次改名为[join $names {、}]，位置和数量不变。"
}
proc ::xiaokai::drc::commandWireAttachments {row state} {
    set wire [dict get $row object]; set result {}
    set it [$wire NewOffPageConnectorsIter $state]
    try {
        for {set off [$it NextOffPageConnector $state]} {$off ne "NULL"} {set off [$it NextOffPageConnector $state]} {
            set symbol [$off GetSymbol $state]
            if {[cstring $off GetName] ne [dict get $row name] || [cstring $symbol GetName] ni {OFFPAGELEFT-R OFFPAGELEFT-L}} {error "导线已有其他类型或不同网名的连接符，不能自动搬移或改名。"}
            lappend result [list $off [commandXY [$off GetLocation $state]]]
        }
    } finally {delete_DboWireOffPageConnectorsIter $it}
    return $result
}
proc ::xiaokai::drc::commandWireFree {row state {allowInputs 0}} {
    set wire [dict get $row object]
    foreach spec {
        {NewConnectedWiresIter NextWire delete_DboWireConnectedWiresIter}
        {NewPortInstsIter NextPortInst delete_DboWirePortInstsIter}
        {NewBusEntriesIter NextBusEntry delete_DboWireBusEntriesIter}
        {NewPortsIter NextPort delete_DboWirePortsIter}
        {NewGlobalsIter NextGlobal delete_DboWireGlobalsIter}
        {NewOffPageConnectorsIter NextOffPageConnector delete_DboWireOffPageConnectorsIter}
    } {
        lassign $spec maker next cleanup
        if {$allowInputs && $maker eq "NewOffPageConnectorsIter"} {commandWireAttachments $row $state; continue}
        if {$maker in {NewPortInstsIter NewPortsIter}} {set it [$wire $maker $state $::IterDefs_ALL]} else {set it [$wire $maker $state]}
        try {if {[$it $next $state] ne "NULL"} {error "导线 [dict get $row name] 已有连接；不能直接移动或追加端口，以免改错连接。"}} finally {$cleanup $it}
    }
}
proc ::xiaokai::drc::commandSetWire {row points aliasPoints} {
    set wire [dict get $row object]
    for {set i 0} {$i < 2} {incr i} {
        set p [DboTclHelper_sMakeCPoint {*}[lindex $points $i]]
        try {reviewCheckStatus [$wire SetPoint $i $p]} finally {DboTclHelper_sDeleteCPoint $p}
    }
    foreach alias [dict get $row aliases] xy $aliasPoints {
        set p [DboTclHelper_sMakeCPoint {*}$xy]
        try {reviewCheckStatus [[lindex $alias 0] SetLocation $p]} finally {DboTclHelper_sDeleteCPoint $p}
    }
    set dx [expr {[lindex $points 0 0]-[lindex [dict get $row points] 0 0]}]
    set dy [expr {[lindex $points 0 1]-[lindex [dict get $row points] 0 1]}]
    foreach attachment [get $row attachments {}] {
        lassign $attachment off xy
        set p [DboTclHelper_sMakeCPoint [expr {[lindex $xy 0]+$dx}] [expr {[lindex $xy 1]+$dy}]]
        try {reviewCheckStatus [$off SetLocation $p]} finally {DboTclHelper_sDeleteCPoint $p}
    }
}
proc ::xiaokai::drc::commandMoveWires {context layout} {
    set rows [commandTargetRows $context $layout]; set page [dict get $context page]
    set s [DboState]; set modified {}
    try {
        set allPoints {}; set ids {}; set width 0
        set enriched {}
        foreach row $rows {
            commandSimpleWire $row; commandWireFree $row $s 1
            dict set row attachments [commandWireAttachments $row $s]
            lappend enriched $row
            lappend ids [dict get $row id]
            foreach attached [dict get $row attachments] {lappend ids [[lindex $attached 0] GetId $s]}
            lappend allPoints {*}[dict get $row points]
            lassign [commandBounds [dict get $row points]] l t r b
            set width [expr {max($width,$r-$l)}]
        }
        set rows [lsort -command ::xiaokai::drc::commandRowOrder $enriched]
        set spacing [dict get $layout spacing]; set height [expr {([llength $rows]-1)*$spacing+30}]
        # Without a reference preserve the original left/top anchor where it is
        # free; otherwise search around the original batch with full avoidance.
        set bounds [commandBounds $allPoints]; lassign $bounds l t r b
        set boxes [commandObjects $page $ids]; set size [$page GetDocUnits]
        try {set pw [DboTclHelper_sGetCSizeX $size]; set ph [DboTclHelper_sGetCSizeY $size]} finally {DboTclHelper_sDeleteCSize $size}
        if {![dict exists $layout _picked] && [dict get $layout near_index] == -1 && [dict get $layout direction] eq "auto" && [commandFits $boxes $pw $ph $l [expr {$t-15}] $width $height]} {
            set x $l; set y [expr {$t-15}]
        } else {lassign [commandLayoutSpace $context $width $height $layout $ids $bounds] x y}
        commandValidateContext $context
        set targetY [expr {$y+15}]
        foreach row $rows {
            set points [dict get $row points]; set a [lindex $points 0]; set b [lindex $points 1]
            set dx [expr {$x-min([lindex $a 0],[lindex $b 0])}]; set dy [expr {$targetY-[lindex $a 1]}]
            set nextPoints [lmap p $points {list [expr {[lindex $p 0]+$dx}] [expr {[lindex $p 1]+$dy}]}]
            set aliasPoints [lmap a [dict get $row aliases] {list [expr {[lindex $a 1 0]+$dx}] [expr {[lindex $a 1 1]+$dy}]}]
            lappend modified $row
            commandSetWire $row $nextPoints $aliasPoints
            set wire [dict get $row object]
            if {[commandXY [$wire GetStartPoint $s]] ne [lindex $nextPoints 0] || [commandXY [$wire GetEndPoint $s]] ne [lindex $nextPoints 1]} {error "移动后端点复查失败。"}
            if {[cstring [lindex [lindex [dict get $row aliases] 0] 0] GetName] ne [dict get $row name]} {error "移动后网名复查失败。"}
            foreach attachment [dict get $row attachments] {
                set off [lindex $attachment 0]; set connected [$off GetWire $s]
                if {$connected eq "NULL" || [$connected GetId $s] != [dict get $row id]} {error "移动后页间连接符连接复查失败。"}
            }
            incr targetY $spacing
        }
        reviewCheckStatus [$page MarkModified]
    } on error {msg opts} {
        foreach row [lreverse $modified] {
            if {[catch {commandSetWire $row [dict get $row points] [lmap a [dict get $row aliases] {lindex $a 1}]} rollback]} {append msg " 撤回失败：[commandError $rollback]"}
        }
        return -options $opts $msg
    } finally {$s -delete}
    catch {zoomDocumentPoint $page [expr {$x+$width/2}] [expr {$y+$height/2}] [expr {max($width,$height)}]}
    return "已调整 [llength $rows] 条独立导线[commandLayoutDescription $context $layout]，行间距[dict get $layout spacing_mil]mil；导线数量与网名保持不变。网名：[join [lmap r $rows {dict get $r name}] {、}]。"
}
proc ::xiaokai::drc::commandRowOrder {a b} {
    set ay [lindex [dict get $a points] 0 1]; set by [lindex [dict get $b points] 0 1]
    if {$ay != $by} {return [expr {$ay < $by ? -1 : 1}]}
    return [string compare [dict get $a name] [dict get $b name]]
}
proc ::xiaokai::drc::commandInputSymbol {design state {name OFFPAGELEFT-L}} {
    # L's pin sits at the chevron tip; mirrored horizontally it is a left-end input.
    set key [DboTclHelper_sMakeCString $name]
    try {
        set symbol [$design GetOffPageSymbol $key $state]
        if {$symbol eq "NULL"} {
            set roots {}
            foreach envName {CDSROOT CDS_INST_DIR} {if {[info exists ::env($envName)]} {lappend roots $::env($envName)}}
            if {[info exists ::env(SPB_17_4)]} {lappend roots $::env(SPB_17_4)}
            # Locate relative to the loaded Capture database DLL before a
            # known installation fallback; no provider or external credentials.
            foreach loaded [info loaded] {if {[string match -nocase *orDb_Dll* [lindex $loaded 0]]} {lappend roots [file dirname [file dirname [file dirname [lindex $loaded 0]]]]}}
            lappend roots {C:/orcad/Cadence/SPB_17.4}
            set libraryPath ""
            foreach root $roots {set p [file join $root tools capture library capsym.olb]; if {[file exists $p]} {set libraryPath $p; break}}
            if {$libraryPath eq ""} {error "未找到 Cadence capsym.olb 标准页间连接符库。"}
            set path [DboTclHelper_sMakeCString $libraryPath]
            try {set session [$design GetSession $state]; set lib [$session GetLib $path $state]} finally {DboTclHelper_sDeleteCString $path}
            if {$lib eq "NULL"} {error "无法打开标准页间连接符库。"}
            set source [$lib GetOffPageSymbol $key $state]
            if {$source eq "NULL"} {error "标准库中缺少输入型页间连接符。"}
            set copied [$design CopySymbol $source $key $state]
            if {$copied eq "NULL" || ![$state OK]} {error "页间连接符导入失败。"}
            set symbol [$design GetOffPageSymbol $key $state]
        }
        set pin [$symbol GetPin $state]
        if {$pin eq "NULL" || [$pin GetPinType $state] != $::DboValue_DBO_IN} {error "输入型页间连接符的引脚类型校验失败。"}
        commandCheckOffpageGraphic $symbol $state
        return [list $symbol [commandXY [$pin GetHotSpot $state]]]
    } finally {DboTclHelper_sDeleteCString $key}
}
proc ::xiaokai::drc::commandCheckOffpageGraphic {symbol state} {
    # Verify cached graphic geometry too: a symbol name or IN pin type alone
    # does not establish the visible arrow direction.
    set base [DboGraphicObjectToDboSymbol $symbol]
    set it [$base NewVectorsIter $state $::IterDefs_ALL]; set lines {}
    try {
        for {set vector [$it NextVector $state]} {$vector ne "NULL"} {set vector [$it NextVector $state]} {
            if {[$vector GetObjectType] != $::DboBaseObject_LINE} {error "页间连接符图形不是已验证的标准箭头，本次未调整。"}
            set line [DboVectorToDboLine $vector]
            lappend lines [lsort [list [commandXY [$line GetStart $state]] [commandXY [$line GetEnd $state]]]]
        }
    } finally {delete_DboGraphicObjectVectorsIter $it}
    set expected [list {{0 10} {5 5}} {{0 10} {5 15}} {{10 5} {5 10}} {{10 15} {5 10}}]
    if {[lsort $lines] ne [lsort $expected]} {error "页间连接符图形已被修改，无法可靠判定箭头方向，本次未调整。"}
}
proc ::xiaokai::drc::commandOffpageFacing {symbol rotation mirror} {
    if {$symbol ni {OFFPAGELEFT-R OFFPAGELEFT-L} || $rotation ni {0 2} || $mirror ni {0 1}} {return unknown}
    return [expr {($rotation == 2) != ($mirror == 1) ? "right" : "left"}]
}
