# Native adapter for the shared, single-window assistant. No model code is eval'd.
namespace eval ::xiaokai::drc {variable commandChannel ""; variable commandRequests {}; variable commandFocus {}; variable commandPick {}}
proc ::xiaokai::drc::commandEncode {text} {binary encode base64 -maxlen 0 [encoding convertto utf-8 $text]}
proc ::xiaokai::drc::commandOpen {} {
    variable commandChannel
    if {$commandChannel ne ""} {catch {puts $commandChannel SHOW; flush $commandChannel}; return}
    set commandChannel [open |[list [aiHelper] --chat orcad] r+]
    fconfigure $commandChannel -encoding utf-8 -translation lf -blocking 0 -buffering line
    after 100 ::xiaokai::drc::commandRead
}
proc ::xiaokai::drc::commandReply {kind id text} {
    variable commandChannel
    puts $commandChannel "$kind\t$id\t[commandEncode $text]"; flush $commandChannel
}
proc ::xiaokai::drc::commandRead {} {
    variable commandChannel; variable commandRequests
    if {$commandChannel eq ""} {return}
    if {[eof $commandChannel]} {catch {close $commandChannel}; set commandChannel ""; set commandRequests {}; set ::xiaokai::drc::commandPick {}; return}
    while {[gets $commandChannel line] >= 0} {
        set line [string trimright $line \r]
        set fields [split $line \t]; lassign $fields kind id
        if {![regexp {^[a-f0-9]{32}$} $id]} {continue}
        if {$kind eq "CANCEL"} {dict unset commandRequests $id; if {[get $::xiaokai::drc::commandPick id] eq $id} {set ::xiaokai::drc::commandPick {}}; continue}
        if {[catch {
            if {$kind eq "CONTEXT" && [llength $fields] == 2} {
                set commandRequests {}
                set context [commandContext]
                dict set commandRequests $id $context
                commandReply CTX $id [dict get $context json]
            } elseif {$kind eq "ACTION" && [dict exists $commandRequests $id]} {
                set context [dict get $commandRequests $id]; dict unset commandRequests $id
                if {[commandNeedsPick $fields]} {
                    set ::xiaokai::drc::commandPick [dict create id $id context $context fields $fields]
                    commandReply WAIT $id "请在当前原理图上单击放置位置；本窗口会暂时最小化，点击后自动完成。"
                } else {commandReply RESULT $id [commandExecute $context $fields]}
            }
        } msg]} {dict unset commandRequests $id; commandReply ERROR $id "未执行：[commandError $msg]"}
    }
    if {$commandChannel ne ""} {after 100 ::xiaokai::drc::commandRead}
}
proc ::xiaokai::drc::commandError {message} {
    if {[string match {*Invalid method. Must be one of:*} $message] || [string match {wrong # args:*} $message]} {
        return "当前图纸对象的接口不兼容，请更新插件后重试。"
    }
    if {[string length $message] > 240} {return "[string range $message 0 239]…"}
    return $message
}
proc ::xiaokai::drc::commandContext {} {
    variable commandFocus
    set design [activeDesign]; set page [GetActivePage]
    if {$page in {"" NULL}} {error "请先打开要操作的原理图页面。"}
    commandFlushDeletedOffpages $page
    commandFlushDeletedParts $page
    set s [DboState]; set parts {}; set rows {}; set selected {}
    try {
        if {[llength [info commands GetSelectedObjects]]} {foreach object [GetSelectedObjects] {lappend selected [$object GetId $s]}}
        set occurrences [commandPartOccurrences $design $page]
        set it [$page NewPartInstsIter $s]
        try {
            for {set part [$it NextPartInst $s]} {$part ne "NULL"} {set part [$it NextPartInst $s]} {
                if {[llength $parts] >= 5000} {error "当前页器件过多，请缩小操作范围。"}
                set ref [cstring $part GetReference 1]
                set actor $part
                set choices [get $occurrences [$part GetId $s] {}]
                if {[llength $choices] == 1} {lassign [lindex $choices 0] actor ref}
                set value [commandPartValue $actor]
                set chosen [expr {[$part GetId $s] in $selected ? "true" : "false"}]
                set extra [commandPartContextFields $part $actor $design $page $s]
                lappend rows "\{\"index\":[llength $parts],\"ref\":[quote $ref],\"value\":[quote $value],\"selected\":$chosen,$extra\}"
                lappend parts [list [$part GetId $s] $ref]
            }
        } finally {delete_DboPagePartInstsIter $it}
        set wires [commandWires $page]
        set nativeLabels [commandNetLabels $page $wires];set labelRows {}
        foreach label $nativeLabels {
            set chosen [expr {[dict get $label id] in $selected || [dict get $label wire_id] in $selected ? "true" : "false"}]
            set recent [expr {[get $commandFocus design] eq $design && [get $commandFocus page] eq $page && ([dict get $label id] in [get $commandFocus ids {}] || [dict get $label wire_id] in [get $commandFocus ids {}]) ? "true" : "false"}]
            lappend labelRows "\{\"index\":[llength $labelRows],\"name\":[quote [dict get $label name]],\"kind\":[quote [dict get $label kind]],\"point\":\[[join [dict get $label point] ,]\],\"selected\":$chosen,\"recent\":$recent\}"
        }
        set wireRows {};set detachedRows {};set oi [$page NewOffPageConnectorsIter $s]
        try {
            for {set off [$oi NextOffPageConnector $s]} {$off ne "NULL"} {set off [$oi NextOffPageConnector $s]} {
                if {[$off GetWire $s] ne "NULL"} {continue}
                set xy [commandXY [$off GetOffsetHotSpot $s]]
                lappend detachedRows "\{\"name\":[quote [cstring $off GetName]],\"hotspot\":\[[join $xy ,]\],\"connected\":false\}"
            }
        } finally {delete_DboPageOffPageConnectorsIter $oi}
        foreach row $wires {
            set labels {}; foreach name [dict get $row names] {lappend labels [quote $name]}
            set connectors {}
            foreach connector [dict get $row connectors] {
                set direction [commandOffpageFacing [dict get $connector symbol] [dict get $connector rotation] [dict get $connector mirror]]
                lappend connectors "\{\"name\":[quote [dict get $connector name]],\"symbol\":[quote [dict get $connector symbol]],\"facing\":[quote $direction],\"rotation\":[dict get $connector rotation],\"mirror\":[dict get $connector mirror]\}"
            }
            set chosen [expr {[dict get $row id] in $selected ? "true" : "false"}]
            set generated [expr {[regexp {^XKA_[a-f0-9]{12}_[0-9]+$} [dict get $row name]] ? "true" : "false"}]
            set scalar [expr {[dict get $row scalar] ? "true" : "false"}]
            set recent [expr {[get $commandFocus design] eq $design && [get $commandFocus page] eq $page && [dict get $row id] in [get $commandFocus ids {}] ? "true" : "false"}]
            lappend wireRows "\{\"index\":[llength $wireRows],\"names\":\[[join $labels ,]\],\"points\":\[[join [lmap p [dict get $row points] {format {[%s]} [join $p ,]}] ,]\],\"offpage_connectors\":\[[join $connectors ,]\],\"scalar\":$scalar,\"selected\":$chosen,\"recent\":$recent,\"tool_generated\":$generated\}"
        }
        set milPerUnit [expr {1000.0/[commandUnitsPerInch $page]}]
        set style [commandPageStyle $page]
        set defaultSpacing [expr {int(round([dict get $style spacing]*$milPerUnit))}]
        set styleJson "\{\"source\":\"current_page_connected_examples\",\"connected_wire_examples\":[dict get $style examples],\"spacing_votes\":[dict get $style votes],\"spacing_mil\":$defaultSpacing,\"input_style\":\"OFFPAGELEFT-L,rotation=0,mirror=1,tip touches wire\",\"detached_offpages\":\[[join $detachedRows ,]\]\}"
        set json "\{\"platform\":\"orcad\",\"scope\":[quote "$design|$page"],\"page\":[quote [cstring $page GetName]],\"parts\":\[[join $rows ,]\],\"wires\":\[[join $wireRows ,]\],\"labels\":\[[join $labelRows ,]\],\"drawing_style\":$styleJson,\"mil_per_unit\":$milPerUnit,\"default_spacing_mil\":$defaultSpacing,\"placement\":\"blank, near wire, or pick: user clicks schematic after request; recent=true is last successful batch even after rename\"\}"
        return [dict create design $design page $page revision [designRevision $design] parts $parts wires $wires labels $nativeLabels json $json]
    } finally {$s -delete}
}
proc ::xiaokai::drc::commandValidateContext {context} {
    if {[activeDesign] ne [dict get $context design] || [GetActivePage] ne [dict get $context page]} {error "工程或页面已切换，请在目标页面重新发送。"}
    if {[designRevision [dict get $context design]] ne [dict get $context revision]} {error "工程已修改，请重新发送以读取最新页面。"}
}
proc ::xiaokai::drc::commandObjects {page {exclude {}}} {
    set s [DboState]; set boxes {}
    try {
        foreach spec {
            {NewPartInstsIter NextPartInst delete_DboPagePartInstsIter offset}
            {NewWiresIter NextWire delete_DboPageWiresIter wire}
            {NewPortsIter NextPort delete_DboPagePortsIter offset}
            {NewGlobalsIter NextGlobal delete_DboPageGlobalsIter offset}
            {NewOffPageConnectorsIter NextOffPageConnector delete_DboPageOffPageConnectorsIter offset}
            {NewCommentGraphicsIter NextCommentGraphic delete_DboPageCommentGraphicsIter graphic}
            {NewBusEntriesIter NextBusEntry delete_DboPageBusEntriesIter bus_entry}
            {NewTitleBlocksIter NextTitleBlock delete_DboPageTitleBlocksIter offset}
        } {
            lassign $spec maker next cleanup type
            set it [$page $maker $s]
            try {
                for {set object [$it $next $s]} {$object ne "NULL"} {set object [$it $next $s]} {
                    if {[$object GetId $s] in $exclude} {continue}
                    switch $type {
                        wire {
                            set xs {}; set ys {}
                            for {set i 0} {$i < [$object GetPointCount $s]} {incr i} {
                                set point [$object GetPoint $i $s]
                                try {lappend xs [DboTclHelper_sGetCPointX $point]; lappend ys [DboTclHelper_sGetCPointY $point]} finally {DboTclHelper_sDeleteCPoint $point}
                            }
                            if {![llength $xs]} {error "导线缺少端点，不能判断空白位置。"}
                            set box [list [tcl::mathfunc::min {*}$xs] [tcl::mathfunc::min {*}$ys] [tcl::mathfunc::max {*}$xs] [tcl::mathfunc::max {*}$ys]]
                            set aliases [$object NewAliasesIter $s]
                            try {
                                for {set alias [$aliases NextAlias $s]} {$alias ne "NULL"} {set alias [$aliases NextAlias $s]} {
                                    set point [$alias GetLocation $s]
                                    try {
                                        set ax [DboTclHelper_sGetCPointX $point]; set ay [DboTclHelper_sGetCPointY $point]
                                        set span [expr {max(40,[string length [cstring $alias GetName]]*10)}]
                                        lappend boxes [list [expr {$ax-$span}] [expr {$ay-$span}] [expr {$ax+$span}] [expr {$ay+$span}]]
                                    } finally {DboTclHelper_sDeleteCPoint $point}
                                }
                            } finally {delete_DboWireAliasesIter $aliases}
                        }
                        graphic {set box [reviewGraphicRect $object $s]}
                        bus_entry {
                            # DboBusEntry is not a DboGraphicInstance. Its display
                            # bounds may be uncached, so derive bounds from the
                            # persisted page-coordinate endpoints instead.
                            set a [$object GetEntryPoint $s]
                            try {
                                set b [$object GetEndPoint $s]
                                try {
                                    set x [DboTclHelper_sGetCPointX $a]; set y [DboTclHelper_sGetCPointY $a]
                                    set u [DboTclHelper_sGetCPointX $b]; set v [DboTclHelper_sGetCPointY $b]
                                    set box [list [expr {min($x,$u)}] [expr {min($y,$v)}] [expr {max($x,$u)}] [expr {max($y,$v)}]]
                                } finally {DboTclHelper_sDeleteCPoint $b}
                            } finally {DboTclHelper_sDeleteCPoint $a}
                        }
                        default {set box [reviewRect [$object GetOffsetBoundingBox $s]]}
                    }
                    if {$box eq {0 0 0 0}} {error "存在无法读取边界的图元（$maker / $object），不能可靠判断空白位置。"}
                    lappend boxes $box
                    if {$maker eq "NewOffPageConnectorsIter"} {
                        # Native symbol bounds exclude displayed Name text and
                        # its cached display bounds may be empty before redraw.
                        set props [$object NewDisplayPropsIter $s]
                        try {
                            for {set prop [$props NextProp $s]} {$prop ne "NULL"} {set prop [$props NextProp $s]} {
                                if {[$prop GetDisplayType $s] == 0} {continue}
                                lassign [commandXY [$object GetOffsetHotSpot $s]] hx hy
                                set span [expr {max(40,[string length [cstring $object GetName]]*8+20)}]
                                lappend boxes [list [expr {$hx-$span}] [expr {$hy-15}] [expr {$hx+$span}] [expr {$hy+15}]]
                            }
                        } finally {delete_DboDisplayPropsIter $props}
                    }
                }
            } finally {$cleanup $it}
        }
    } finally {$s -delete}
    return $boxes
}
proc ::xiaokai::drc::commandSpace {page width height} {
    set boxes [commandObjects $page]
    # Native page size uses physical units; GetDocUnits returns database units.
    set size [$page GetDocUnits]
    try {set pw [DboTclHelper_sGetCSizeX $size]; set ph [DboTclHelper_sGetCSizeY $size]} finally {DboTclHelper_sDeleteCSize $size}
    set gap 20; set step 20
    for {set y 60} {$y+$height < $ph-60} {incr y $step} {
        for {set x 60} {$x+$width < $pw-60} {incr x $step} {
            set hit 0
            foreach box $boxes {
                lassign $box l t r b
                if {$x-$gap <= $r && $x+$width+$gap >= $l && $y-$gap <= $b && $y+$height+$gap >= $t} {set hit 1; break}
            }
            if {!$hit} {return [list $x $y]}
        }
    }
    error "当前页没有足够的连续空白区域，请整理图纸后重试。"
}
proc ::xiaokai::drc::commandExecuteNative {context fields} {
    if {[llength $fields] != 8} {error "命令字段不完整。"}
    commandValidateContext $context
    lassign $fields kind id action count encodedNames encodedText index tool
    set page [dict get $context page]
    switch $action {
        place_net_wires {
            if {![string is integer -strict $count] || $count < 1 || $count > 32} {error "一次支持1～32条导线。"}
            set text [aiDecode $encodedNames]
            set names [expr {$text eq "" ? {} : [split $text \n]}]
            if {[llength $names] && [llength $names] != $count} {error "网名数量不匹配。"}
            if {![llength $names]} {for {set i 1} {$i <= $count} {incr i} {lappend names XKA_[string range $id 0 11]_$i}}
            foreach name $names {if {![regexp {^[A-Za-z_][A-Za-z0-9_+.-]{0,63}$} $name]} {error "网名包含不支持的字符。"}}
            if {[llength [lsort -unique -nocase $names]] != $count} {error "网名重复。"}
            # Verify names against every existing native net before creating any objects.
            set model [snapshot [dict get $context design]]
            foreach pin [dict get $model pins] {
                foreach name $names {if {[string equal -nocase $name [get $pin net_name]]} {error "网名 $name 已存在，可能形成意外连接；本次未放置。"}}
            }
            commandUnusedAliases [dict get $context design] $names
            set labelWidth 0
            foreach name $names {set labelWidth [expr {max($labelWidth,[string length $name]*6)}]}
            set layout [commandLayout $context $tool]
            set spacing [dict get $layout spacing]
            set width [expr {max(160,$labelWidth+20)}]; set height [expr {($count-1)*$spacing+30}]
            lassign [commandLayoutSpace $context $width $height $layout] x y
            commandValidateContext $context
            commandPlaceWires $page $names $x [expr {$y+15}] $width $spacing
            catch {zoomDocumentPoint $page [expr {$x+$width/2}] [expr {$y+$height/2}] [expr {max($width,$height)}]}
            return "已在当前页空白处放置 $count 条带网名的导线[commandLayoutDescription $context $layout]，行间距[dict get $layout spacing_mil]mil，并核对标签和端点。网名：[join $names {、}]。"
        }
        move_wires {return [commandMoveWires $context [commandLayout $context $tool 1]]}
        add_offpage_inputs {return [commandAddInputs $context [commandLayout $context $tool 1]]}
        set_offpage_direction {return [commandSetOffpageDirection $context [commandLayout $context $tool 1]]}
        rename_wires {return [commandRenameWires $context [commandLayout $context $tool 1] [aiDecode $encodedNames]]}
        rename_net_labels {return [commandRenameNetLabels $context $tool [aiDecode $encodedNames]]}
        set_part_value {return [commandSetPartValue $context $index [aiDecode $encodedText]]}
        copy_parts {return [commandCopyParts $context [commandPartOptions $tool]]}
        move_parts - rotate_parts - mirror_parts - align_parts - distribute_parts {return [commandTransformParts $context $action [commandPartOptions $tool]]}
        set_part_property - rename_parts {return [commandEditPartData $context $action [commandPartOptions $tool]]}
        place_text {
            set text [aiDecode $encodedText]
            if {[string length $text] < 1 || [string length $text] > 80 || [regexp {[\x00-\x1f]} $text]} {error "Text 内容无效。"}
            lassign [reviewTextSize $text] w h
            lassign [commandSpace $page $w $h] x y
            commandValidateContext $context
            commandPlaceText $page $text $x $y $w $h
            catch {zoomDocumentPoint $page $x $y 160}
            return "已在当前页空白处放置红色 Text：$text"
        }
        locate {
            set parts [dict get $context parts]
            if {![string is integer -strict $index] || $index < 0 || $index >= [llength $parts]} {error "器件索引无效。"}
            lassign [lindex $parts $index] partId ref
            set s [DboState]; set it [$page NewPartInstsIter $s]; set box {}
            try {
                for {set part [$it NextPartInst $s]} {$part ne "NULL"} {set part [$it NextPartInst $s]} {
                    if {[$part GetId $s] == $partId} {set box [reviewRect [$part GetOffsetBoundingBox $s]]; break}
                }
            } finally {delete_DboPagePartInstsIter $it; $s -delete}
            if {$box eq ""} {error "目标器件已不存在，请重新发送。"}
            catch {UnSelectAll}
            SelectObjectById $partId
            lassign $box l t r b
            catch {zoomDocumentPoint $page [expr {($l+$r)/2}] [expr {($t+$b)/2}] [expr {max(120,$r-$l,$b-$t)}]}
            return "已选择并定位当前页器件 $ref。"
        }
        open_tool {
            set commands [dict create drc drctoolMenuRun bom bomtoolMenuExport netloc ::netloc::menuRun parts lceda2orcadMenuDialog]
            if {![dict exists $commands $tool]} {error "该工具尚未接入。"}
            after idle [dict get $commands $tool]
            return "已调出对应工具，请按工具提示继续操作。"
        }
        default {error "不支持的命令，未执行。"}
    }
}
proc ::xiaokai::drc::commandUnusedAliases {design names {ignoreAliases {}}} {
    set s [DboState]; set views [$design NewViewsIter $s $::IterDefs_SCHEMATICS]
    try {
        for {set view [$views NextView $s]} {$view ne "NULL"} {set view [$views NextView $s]} {
            set sch [DboViewToDboSchematic $view]; set pages [$sch NewPagesIter $s]
            try {
                for {set page [$pages NextPage $s]} {$page ne "NULL"} {set page [$pages NextPage $s]} {
                    foreach spec {
                        {NewOffPageConnectorsIter NextOffPageConnector delete_DboPageOffPageConnectorsIter}
                        {NewGlobalsIter NextGlobal delete_DboPageGlobalsIter}
                        {NewPortsIter NextPort delete_DboPagePortsIter}
                    } {
                        lassign $spec maker next cleanup
                        set symbols [$page $maker $s]
                        try {
                            for {set symbol [$symbols $next $s]} {$symbol ne "NULL"} {set symbol [$symbols $next $s]} {
                                if {$symbol in $ignoreAliases} {continue}
                                set actual [cstring $symbol GetName]
                                foreach name $names {if {[string equal -nocase $actual $name]} {error "网名 $name 已被连接符使用，本次未放置。"}}
                            }
                        } finally {$cleanup $symbols}
                    }
                    set wires [$page NewWiresIter $s]
                    try {
                        for {set wire [$wires NextWire $s]} {$wire ne "NULL"} {set wire [$wires NextWire $s]} {
                            set aliases [$wire NewAliasesIter $s]
                            try {
                                for {set alias [$aliases NextAlias $s]} {$alias ne "NULL"} {set alias [$aliases NextAlias $s]} {
                                    if {$alias in $ignoreAliases} {continue}
                                    set actual [cstring $alias GetName]
                                    foreach name $names {if {[string equal -nocase $actual $name]} {error "网名 $name 已存在，本次未放置。"}}
                                }
                            } finally {delete_DboWireAliasesIter $aliases}
                        }
                    } finally {delete_DboPageWiresIter $wires}
                }
            } finally {delete_DboSchematicPagesIter $pages}
        }
    } finally {delete_DboLibViewsIter $views; $s -delete}
}
proc ::xiaokai::drc::commandPlaceWires {page names x y width {spacing 40}} {
    set s [DboState]; set created {}; set font [DboTclHelper_sMakeLOGFONT Arial -7 0 0 0 400 0 0 0 0 0 0 0 0]
    try {
        foreach name $names {
            set a [DboTclHelper_sMakeCPoint $x $y]; set b [DboTclHelper_sMakeCPoint [expr {$x+$width}] $y]
            set c [DboTclHelper_sMakeCString $name]
            try {
                set wire [$page NewWireScalar $s $a $b]
                if {$wire eq "NULL" || ![$s OK]} {error "原生导线创建失败。"}
                lappend created $wire
                set alias [$wire NewAlias $s $c $a $font 0 $::DboValue_DEFAULT_OBJECT_COLOR]
                if {$alias eq "NULL" || ![$s OK] || [cstring $alias GetName] ne $name} {error "原生网名写入失败。"}
                set start [$wire GetStartPoint $s]; set end [$wire GetEndPoint $s]
                try {
                    if {[DboTclHelper_sGetCPointX $start] != $x || [DboTclHelper_sGetCPointY $start] != $y || [DboTclHelper_sGetCPointX $end] != $x+$width || [DboTclHelper_sGetCPointY $end] != $y} {error "导线端点复查失败。"}
                } finally {DboTclHelper_sDeleteCPoint $start; DboTclHelper_sDeleteCPoint $end}
            } finally {DboTclHelper_sDeleteCPoint $a; DboTclHelper_sDeleteCPoint $b; DboTclHelper_sDeleteCString $c}
            incr y $spacing
        }
        reviewCheckStatus [$page MarkModified]
    } on error {msg options} {
        foreach wire [lreverse $created] {if {[catch {reviewCheckStatus [$page DeleteWire $wire]} err]} {append msg " 撤回失败：$err"}}
        return -options $options $msg
    } finally {DboTclHelper_sDeleteLOGFONT $font; $s -delete}
    return [llength $created]
}
proc ::xiaokai::drc::commandPlaceText {page text x y width height} {
    set s [DboState]; set inst NULL
    set rect [DboTclHelper_sMakeCRect $x $y [expr {$x+$width}] [expr {$y+$height}]]
    set point [DboTclHelper_sMakeCPoint $x $y]; set value [DboTclHelper_sMakeCString $text]
    set font [DboTclHelper_sMakeLOGFONT {Microsoft YaHei} -7 0 0 0 400 0 0 0 134 0 0 0 0]
    try {
        set inst [$page NewGraphicCommentTextInst $s $rect $point $value $font 0]
        if {$inst eq "NULL" || ![$s OK]} {error "原生 Text 创建失败。"}
        reviewCheckStatus [$inst SetColor $::DboValue_COLOR8]
        if {[reviewText $inst] ne $text || [$inst GetColor $s] != $::DboValue_COLOR8} {error "Text 内容或颜色复查失败。"}
        reviewCheckStatus [$page MarkModified]
    } on error {msg options} {
        if {$inst ne "NULL" && [catch {reviewCheckStatus [$page DeleteCommentGraphic $inst]} err]} {append msg " 撤回失败：$err"}
        return -options $options $msg
    } finally {
        DboTclHelper_sDeleteCRect $rect; DboTclHelper_sDeleteCPoint $point
        DboTclHelper_sDeleteCString $value; DboTclHelper_sDeleteLOGFONT $font; $s -delete
    }
}
