# Native component editing. The model selects indexed objects, never native code.
namespace eval ::xiaokai::drc {
    variable commandPartPropertyNames {Value {PCB Footprint} Description Manufacturer MPN {Part Number} Tolerance Voltage DNP {LCSC Part Number} Datasheet}
    variable commandDeletedParts {}
}
proc ::xiaokai::drc::commandPartContextFields {part actor design page state} {
    variable commandFocus;variable commandPartPropertyNames
    set properties {}
    foreach name $commandPartPropertyNames {lassign [commandPartProperty $actor $name] exists value;if {$exists} {lappend properties "[quote $name]:[quote $value]"}}
    set recent [expr {[get $commandFocus design] eq $design && [get $commandFocus page] eq $page && [$part GetId $state] in [get $commandFocus ids {}] ? "true" : "false"}]
    set point [commandXY [$part GetLocation $state]];set box [commandPartBox $part $state]
    return "\"point\":\[[join $point ,]\],\"bbox\":\[[join $box ,]\],\"rotation_degrees\":[expr {[$part GetRotation $state]*90}],\"mirror\":[$part GetMirror $state],\"recent\":$recent,\"properties\":\{[join $properties ,]\}"
}
proc ::xiaokai::drc::commandPartProperty {object name} {
    set key [DboTclHelper_sMakeCString $name];set value [DboTclHelper_sMakeCString]
    try {
        set status [$object GetEffectivePropStringValue $key $value]
        try {return [list [$status OK] [DboTclHelper_sGetConstCharPtr $value]]} finally {$status -delete}
    } finally {DboTclHelper_sDeleteCString $key;DboTclHelper_sDeleteCString $value}
}
proc ::xiaokai::drc::commandWritePartProperty {object name value} {
    set key [DboTclHelper_sMakeCString $name];set next [DboTclHelper_sMakeCString $value]
    try {
        reviewCheckStatus [$object SetEffectivePropStringValue $key $next]
        if {[commandPartProperty $object $name] ne [list 1 $value]} {error "器件属性写入回读不一致。"}
    } finally {DboTclHelper_sDeleteCString $key;DboTclHelper_sDeleteCString $next}
}
proc ::xiaokai::drc::commandPartById {page id state} {
    set it [$page NewPartInstsIter $state]
    try {
        for {set part [$it NextPartInst $state]} {$part ne "NULL"} {set part [$it NextPartInst $state]} {
            if {[$part GetId $state] == $id} {return $part}
        }
    } finally {delete_DboPagePartInstsIter $it}
    error "目标器件已不存在，请重新发送。"
}
proc ::xiaokai::drc::commandPartBox {part state} {
    set points {};lassign [reviewRect [$part GetOffsetBoundingBox $state]] l t r b
    lappend points [list $l $t] [list $r $b]
    set it [$part NewPinsIter $state]
    try {
        for {set pin [$it NextPin $state]} {$pin ne "NULL"} {set pin [$it NextPin $state]} {lappend points [commandXY [$pin GetOffsetHotSpot $state]]}
    } finally {delete_DboPartInstPinsIter $it}
    # Include reference/value text, whose cached native bounds may be empty.
    set x [commandBounds $points];lassign $x l t r b
    return [list [expr {$l-10}] [expr {$t-20}] [expr {$r+10}] [expr {$b+20}]]
}
proc ::xiaokai::drc::commandPartTargets {context options state} {
    set indices [get $options target_indices {}];set rows {};set occurrences [commandPartOccurrences [dict get $context design] [dict get $context page]]
    if {[llength $indices] < 1 || [llength $indices] > 32 || [llength [lsort -unique $indices]] != [llength $indices]} {error "请指定1～32个不重复的器件。"}
    foreach index $indices {
        if {![string is integer -strict $index] || $index < 0 || $index >= [llength [dict get $context parts]]} {error "器件索引无效。"}
        lassign [lindex [dict get $context parts] $index] id ref
        set part [commandPartById [dict get $context page] $id $state]
        if {![$part IsPrimitive $state] || [$part GetObjectType] != $::DboBaseObject_PLACED_INSTANCE} {error "$ref 是分层模块或非标准器件，不能用器件编辑命令修改。"}
        set choices [get $occurrences $id {}]
        if {[llength $choices] != 1 || ![$part IsVariantPropMapEmpty]} {error "$ref 存在复用分层或变体，需要先明确对应实例。"}
        lassign [lindex $choices 0] actor actual
        if {$actual ne $ref || ![$actor IsVariantPropMapEmpty]} {error "$ref 的实例或变体属性已变化，请重新读取。"}
        lappend rows [dict create id $id ref $ref object $part actor $actor location [commandXY [$part GetLocation $state]] box [commandPartBox $part $state] rotation [$part GetRotation $state] mirror [$part GetMirror $state] raw_ref [cstring $part GetReference] occurrence_ref [cstring $actor GetReference]]
    }
    return $rows
}
proc ::xiaokai::drc::commandPartOptions {encoded} {
    package require json
    set options [json::json2dict [aiDecode $encoded]]
    foreach key {spacing_mil clearance_mil gap_mil} {
        if {[dict exists $options $key] && (![string is integer -strict [dict get $options $key]] || [dict get $options $key] < 20 || [dict get $options $key] > 10000)} {error "器件间距须为20～10000mil。"}
    }
    foreach key {dx_mil dy_mil} {
        if {[dict exists $options $key] && (![string is integer -strict [dict get $options $key]] || abs([dict get $options $key]) > 10000)} {error "器件位移须为±10000mil以内的整数。"}
    }
    if {[get $options placement blank] ni {blank pick} || [get $options direction auto] ni {auto right left above below} || [get $options layout row] ni {row column grid}} {error "器件放置参数无效。"}
    return $options
}
proc ::xiaokai::drc::commandPartMil {page value} {return [expr {int(round($value*[commandUnitsPerInch $page]/1000.0/10))*10}]}
proc ::xiaokai::drc::commandPartLocation {part xy} {
    set point [DboTclHelper_sMakeCPoint {*}$xy]
    set state [DboState]
    try {
        reviewCheckStatus [$part SetLocation $point]
        if {[commandXY [$part GetLocation $state]] ne $xy} {error "图元位置写入回读不一致。"}
    } finally {DboTclHelper_sDeleteCPoint $point;$state -delete}
}
proc ::xiaokai::drc::commandPartReference {object ref} {
    set value [DboTclHelper_sMakeCString $ref]
    try {
        reviewCheckStatus [$object SetReference $value]
        if {![string equal $ref [cstring $object GetReference]]} {error "器件位号写入回读不一致。"}
    } finally {DboTclHelper_sDeleteCString $value}
}
proc ::xiaokai::drc::commandPartLogical {model {keepIds {}}} {
    set pins {};set nets {}
    foreach pin [dict get $model pins] {
        if {![get $pin is_primitive 1] || ($keepIds ne "" && [dict get $pin _part_id] ni $keepIds)} {continue}
        set id [list [get $pin hierarchy_path] [get $pin schematic] [get $pin sheet_name] [dict get $pin _part_id] [get $pin pin_number] [get $pin pin_name]]
        lappend pins [list $id [get $pin no_connect] [get $pin pin_type]]
        if {[get $pin flat_net] ne ""} {dict lappend nets [dict get $pin flat_net] $id}
    }
    set groups {};dict for {net members} $nets {lappend groups [lsort $members]}
    return [list [lsort $pins] [lsort $groups]]
}
proc ::xiaokai::drc::commandPartModel {context} {
    DboTclHelper_sEvalPage [dict get $context page]
    snapshot [dict get $context design]
    return [snapshot [dict get $context design]]
}
proc ::xiaokai::drc::commandPartRefs {model} {
    set refs {};foreach pin [dict get $model pins] {foreach key {refdes package_ref instance_ref} {set ref [get $pin $key];if {$ref ne ""} {dict set refs [string toupper $ref] 1}}}
    set state [DboState]
    try {
        set all {};set root [[activeDesign] GetRootOccurrence $state]
        if {$root ne "NULL"} {commandCollectOccurrences $root -1 all $state}
        dict for {id rows} $all {foreach row $rows {dict set refs [string toupper [lindex $row 1]] 1}}
    } finally {$state -delete}
    return $refs
}
proc ::xiaokai::drc::commandNextPartRef {source refsVar} {
    upvar 1 $refsVar refs
    if {![regexp {^([A-Za-z_]+)([0-9]+|\?)([A-Za-z]*)$} $source -> prefix number unit]} {error "无法识别 $source 的位号前缀，请指定新位号。"}
    set maximum 0
    foreach ref [dict keys $refs] {if {[regexp {^([A-Za-z_]+)([0-9]+)([A-Za-z]*)$} $ref -> p n u] && [string equal -nocase $p $prefix]} {set maximum [expr {max($maximum,int($n))}]}}
    set next ${prefix}[expr {$maximum+1}];dict set refs [string toupper $next] 1;return $next
}
proc ::xiaokai::drc::commandCopyPartOverrides {source target} {
    # NewPlacedInst copies raw properties; preserve editable occurrence overrides too.
    set state [DboState];set it [$source NewEffectivePropsIter $state]
    set name [DboTclHelper_sMakeCString];set value [DboTclHelper_sMakeCString]
    set type [DboTclHelper_sMakeDboValueType];set editable [DboTclHelper_sMakeInt]
    try {
        while {1} {
            set status [$it NextEffectiveProp $name $value $type $editable]
            try {set ok [$status OK]} finally {$status -delete}
            if {!$ok} {break}
            set key [DboTclHelper_sGetConstCharPtr $name];set text [DboTclHelper_sGetConstCharPtr $value]
            if {![DboTclHelper_sGetInt $editable] || [string tolower $key] in {reference {part reference} {reference designator} {package reference} {instance reference} id location rotation mirror}} {continue}
            if {[commandPartProperty $target $key] ne [list 1 $text]} {commandWritePartProperty $target $key $text}
        }
    } finally {
        delete_DboEffectivePropsIter $it;$state -delete
        DboTclHelper_sDeleteCString $name;DboTclHelper_sDeleteCString $value
        DboTclHelper_sDeleteDboValueType $type;DboTclHelper_sDeleteInt $editable
    }
}
proc ::xiaokai::drc::commandNewPartCopy {page source ref xy state} {
    set part [$page NewPlacedInst [DboPartInstToDboPlacedInst [dict get $source object]] $state]
    if {$part eq "NULL" || ![$state OK]} {error "原生器件复制失败。"}
    try {
        commandPartReference $part $ref
        commandPartLocation $part $xy
        commandCopyPartOverrides [dict get $source actor] $part
        return [$part GetId $state]
    } on error {msg opts} {commandDeleteNewPart $page $part;return -options $opts $msg}
}
proc ::xiaokai::drc::commandDeleteNewPart {page part} {
    variable commandDeletedParts
    $part Increment
    try {$part Disconnect;reviewCheckStatus [$page DeletePartInst $part];dict lappend commandDeletedParts $page $part} on error {msg opts} {$part Decrement;return -options $opts $msg}
}
proc ::xiaokai::drc::commandFlushDeletedParts {page} {
    variable commandDeletedParts
    if {![dict exists $commandDeletedParts $page]} {return 0}
    DboTclHelper_sEvalPage $page;snapshot [activeDesign];snapshot [activeDesign]
    set held [dict get $commandDeletedParts $page];dict unset commandDeletedParts $page
    foreach part $held {$part Decrement};return 1
}
proc ::xiaokai::drc::commandPartBlank {context options width height exclude anchor} {
    set page [dict get $context page]
    if {[dict exists $options _picked]} {
        lassign [dict get $options _picked] x y
        set x [expr {int(round($x/10.0))*10}];set y [expr {int(round($y/10.0))*10}]
        set size [$page GetDocUnits]
        try {set pw [DboTclHelper_sGetCSizeX $size];set ph [DboTclHelper_sGetCSizeY $size]} finally {DboTclHelper_sDeleteCSize $size}
        if {![commandFits [commandObjects $page $exclude] $pw $ph $x $y $width $height 10]} {error "点击位置放不下器件或与现有图元重叠，请换个空白处。"}
        return [list $x $y]
    }
    set near [get $options near_part_index -1]
    if {$near >= 0} {
        if {![string is integer -strict $near] || $near >= [llength [dict get $context parts]]} {error "参考器件索引无效。"}
        set state [DboState]
        try {set anchor [commandPartBox [commandPartById $page [lindex [lindex [dict get $context parts] $near] 0] $state] $state]} finally {$state -delete}
    }
    set layout [dict create near_index -1 direction [get $options direction auto] clearance [expr {max(10,[commandPartMil $page [get $options clearance_mil 200]])}]]
    return [commandLayoutSpace $context $width $height $layout $exclude $anchor]
}
proc ::xiaokai::drc::commandRevealParts {context ids state} {
    set points {}
    foreach id $ids {
        lassign [commandPartBox [commandPartById [dict get $context page] $id $state] $state] l t r b
        lappend points [list $l $t] [list $r $b]
    }
    lassign [commandBounds $points] l t r b
    catch {UnSelectAll};foreach id $ids {catch {SelectObjectById $id}}
    catch {zoomDocumentPoint [dict get $context page] [expr {($l+$r)/2}] [expr {($t+$b)/2}] [expr {max(160,$r-$l,$b-$t)}]}
}
proc ::xiaokai::drc::commandCopyParts {context options} {
    set page [dict get $context page];set design [dict get $context design];set state [DboState];set created {};set refsOut {}
    try {
        set sources [commandPartTargets $context $options $state];set count [get $options count 1]
        if {![string is integer -strict $count] || $count < 1 || $count > 16 || $count*[llength $sources] > 32} {error "一次最多复制32个器件，每个源器件最多16份。"}
        set before [snapshot $design];set oldIds [lsort -unique [lmap p [dict get $before pins] {dict get $p _part_id}]];set refs [commandPartRefs $before]
        set supplied [get $options references {}]
        if {[llength $supplied] && [llength $supplied] != $count*[llength $sources]} {error "新位号数量与复制数量不一致。"}
        set all {};set w 0;set h 0
        for {set copy 0} {$copy < $count} {incr copy} {foreach row $sources {
            if {[llength $supplied]} {
                set ref [lindex $supplied [llength $all]]
                if {![regexp {^[A-Za-z_]+[1-9][0-9]*$} $ref] || [dict exists $refs [string toupper $ref]]} {error "新位号 $ref 无效或已存在。"}
                dict set refs [string toupper $ref] 1
            } else {set ref [commandNextPartRef [dict get $row ref] refs]}
            lassign [dict get $row box] l t r b;set w [expr {max($w,$r-$l)}];set h [expr {max($h,$b-$t)}]
            lappend all [list $row $ref]
        }}
        set n [llength $all];set gap [expr {max(10,[commandPartMil $page [get $options spacing_mil 200]])}]
        switch [get $options layout row] {column {set columns 1} grid {set columns [expr {int(ceil(sqrt($n)))}]} default {set columns $n}}
        set lines [expr {int(ceil($n/double($columns)))}];set width [expr {$columns*$w+($columns-1)*$gap}];set height [expr {$lines*$h+($lines-1)*$gap}]
        lassign [commandPartBlank $context $options $width $height {} [dict get [lindex $sources end] box]] x y
        commandValidateContext $context;set i 0
        foreach item $all {
            lassign $item row ref;lassign [dict get $row box] l t r b;lassign [dict get $row location] px py
            set xy [list [expr {$x+($i%$columns)*($w+$gap)+$px-$l}] [expr {$y+($i/$columns)*($h+$gap)+$py-$t}]]
            lappend created [commandNewPartCopy $page $row $ref $xy $state];lappend refsOut $ref;incr i
        }
        reviewCheckStatus [$page MarkModified];set after [commandPartModel $context]
        if {[commandPartLogical $before $oldIds] ne [commandPartLogical $after $oldIds]} {error "复制影响了原有引脚连接，已撤回复制件。"}
        set occurrences [commandPartOccurrences $design $page]
        foreach id $created ref $refsOut item $all {
            set part [commandPartById $page $id $state];set choices [get $occurrences $id {}]
            if {[llength $choices] != 1 || ![string equal -nocase $ref [cstring [lindex [lindex $choices 0] 0] GetReference]]} {error "复制件位号未正确写入实例，已撤回。"}
            set actor [lindex [lindex $choices 0] 0]
            set sourceChoices [dict get $occurrences [dict get [lindex $item 0] id]]
            if {[commandPartValue $actor] ne [commandPartValue [lindex [lindex $sourceChoices 0] 0]]} {error "复制件Value与源器件不一致，已撤回。"}
        }
        set oldNets {};foreach p [dict get $before pins] {if {[get $p flat_net] ne ""} {dict set oldNets [dict get $p flat_net] 1}}
        foreach p [dict get $after pins] {if {[dict get $p _part_id] in $created && ![get $p is_power 0] && [dict exists $oldNets [get $p flat_net]]} {error "复制件意外接入已有信号网络，已撤回。"}}
        set ::xiaokai::drc::commandFocus [dict create design $design page $page ids $created]
        commandRevealParts $context $created $state
    } on error {msg opts} {
        foreach id [lreverse $created] {if {[catch {commandDeleteNewPart $page [commandPartById $page $id $state]} rollback]} {append msg " 撤回复制件失败：[commandError $rollback]"}}
        if {[llength $created]} {commandFlushDeletedParts $page}
        return -options $opts $msg
    } finally {$state -delete}
    return "已复制 [llength $created] 个器件：[join $refsOut {、}]。保留源器件参数，放在空白处；原器件和原连接已复查。"
}
proc ::xiaokai::drc::commandPartLeadWires {context rows model state} {
    set ids [lmap row $rows {dict get $row id}];set wires [commandWires [dict get $context page]];set found {};set queue {}
    foreach wire $wires {
        foreach pin [dict get $model pins] {
            if {[dict get $pin _part_id] in $ids && [commandPointOnRow $wire [dict get $pin _pin_point]]} {lappend queue [dict get $wire id];break}
        }
    }
    set byId {};foreach wire $wires {dict set byId [dict get $wire id] $wire}
    while {[llength $queue]} {
        set id [lindex $queue 0];set queue [lrange $queue 1 end]
        if {[dict exists $found $id]} {continue}
        if {![dict exists $byId $id]} {error "导线跨越了当前页可读取范围。"}
        set row [dict get $byId $id];set wire [dict get $row object]
        if {![dict get $row scalar]} {error "器件连着总线，当前移动需先明确总线连接。"}
        set it [$wire NewConnectedWiresIter $state]
        try {for {set other [$it NextWire $state]} {$other ne "NULL"} {set other [$it NextWire $state]} {lappend queue [$other GetId $state]}} finally {delete_DboWireConnectedWiresIter $it}
        set it [$wire NewBusEntriesIter $state]
        try {if {[$it NextBusEntry $state] ne "NULL"} {error "器件引线连接总线入口，当前不自动改动。"}} finally {delete_DboWireBusEntriesIter $it}
        # Check physical pins on this page, never cross-page coordinates.
        foreach pin [dict get $model pins] {
            if {[get $pin schematic] eq [cstring [[dict get $context page] GetOwner] GetName] && [get $pin sheet_name] eq [cstring [dict get $context page] GetName] && [dict get $pin _part_id] ni $ids && [commandPointOnRow $row [dict get $pin _pin_point]]} {
                error "引线连到未选中的器件 [dict get $pin refdes]，请一起选中相关器件后移动；本次未修改。"
            }
        }
        set symbols {}
        foreach spec {{NewOffPageConnectorsIter NextOffPageConnector delete_DboWireOffPageConnectorsIter} {NewGlobalsIter NextGlobal delete_DboWireGlobalsIter} {NewPortsIter NextPort delete_DboWirePortsIter}} {
            lassign $spec maker next cleanup
            if {$maker eq "NewPortsIter"} {set it [$wire $maker $state $::IterDefs_ALL]} else {set it [$wire $maker $state]}
            try {for {set sym [$it $next $state]} {$sym ne "NULL"} {set sym [$it $next $state]} {lappend symbols [dict create id [$sym GetId $state] object $sym location [commandXY [$sym GetLocation $state]]]}} finally {$cleanup $it}
        }
        dict set row symbols $symbols;dict set found $id $row
    }
    return [dict values $found]
}
proc ::xiaokai::drc::commandPartShiftWire {row dx dy} {
    set wire [dict get $row object];set i 0
    foreach xy [dict get $row points] {
        set point [DboTclHelper_sMakeCPoint [expr {[lindex $xy 0]+$dx}] [expr {[lindex $xy 1]+$dy}]]
        try {reviewCheckStatus [$wire SetPoint $i $point]} finally {DboTclHelper_sDeleteCPoint $point};incr i
    }
    foreach alias [dict get $row aliases] {
        set xy [lindex $alias 1];commandPartLocation [lindex $alias 0] [list [expr {[lindex $xy 0]+$dx}] [expr {[lindex $xy 1]+$dy}]]
    }
    foreach sym [dict get $row symbols] {
        set xy [dict get $sym location];commandPartLocation [dict get $sym object] [list [expr {[lindex $xy 0]+$dx}] [expr {[lindex $xy 1]+$dy}]]
    }
}
proc ::xiaokai::drc::commandPartRestoreWire {page original state} {
    foreach row [commandWires $page] {if {[dict get $row id] == [dict get $original id]} {
        set i 0;foreach xy [dict get $original points] {
            set p [DboTclHelper_sMakeCPoint {*}$xy]
            try {reviewCheckStatus [[dict get $row object] SetPoint $i $p]} finally {DboTclHelper_sDeleteCPoint $p};incr i
        }
        foreach a [dict get $original aliases] {
            foreach current [dict get $row aliases] {if {[lindex $a 3] == [lindex $current 3]} {commandPartLocation [lindex $current 0] [lindex $a 1]}}
        }
        foreach sym [dict get $original symbols] {commandPartLocation [dict get $sym object] [dict get $sym location]}
        return
    }}
    error "恢复时未找到原导线。"
}
proc ::xiaokai::drc::commandPartsBounds {rows wires} {
    set points {}
    foreach row $rows {lassign [dict get $row box] l t r b;lappend points [list $l $t] [list $r $b]}
    foreach wire $wires {lappend points {*}[dict get $wire points];foreach sym [dict get $wire symbols] {lappend points [dict get $sym location]}}
    return [commandBounds $points]
}
proc ::xiaokai::drc::commandTransformParts {context action options} {
    set page [dict get $context page];set design [dict get $context design];set state [DboState];set originals {};set changedWires {};set changed 0
    try {
        set rows [commandPartTargets $context $options $state];set before [snapshot $design];set ids [lmap row $rows {dict get $row id}]
        set clusters {};set allWires {};set seenWires {};set translations {}
        if {$action eq "move_parts"} {set sets [list $rows]} else {set sets [lmap row $rows {list $row}]}
        foreach subset $sets {
            set wires [commandPartLeadWires $context $subset $before $state]
            if {$action in {rotate_parts mirror_parts} && [llength $wires]} {error "旋转或镜像会改变已连接引脚位置，请先处理引线；本次未修改。移动可连同独立引线一起操作。"}
            foreach w $wires {
                if {[dict get $w id] in $seenWires} {error "多个目标共享引线，不能分别对齐或分布；可以一起移动。"}
                lappend seenWires [dict get $w id];lappend allWires $w
            }
            lappend clusters [list $subset $wires [commandPartsBounds $subset $wires]]
        }
        set exclude $ids
        foreach wire $allWires {lappend exclude [dict get $wire id];foreach sym [dict get $wire symbols] {lappend exclude [dict get $sym id]}}
        if {$action eq "move_parts"} {
            set cluster [lindex $clusters 0];lassign [lindex $cluster 2] l t r b
            if {[dict exists $options dx_mil] || [dict exists $options dy_mil]} {
                if {![dict exists $options dx_mil] || ![dict exists $options dy_mil]} {error "请同时指定水平与垂直位移。"}
                set dx [commandPartMil $page [dict get $options dx_mil]];set dy [commandPartMil $page [dict get $options dy_mil]]
                if {$dx == 0 && $dy == 0} {error "位移小于当前器件网格，请指定更大的距离。"}
            } else {
                lassign [commandPartBlank $context $options [expr {$r-$l}] [expr {$b-$t}] $exclude [lindex $cluster 2]] x y
                set dx [expr {$x-$l}];set dy [expr {$y-$t}]
            }
            foreach row $rows {dict set translations [dict get $row id] [list $dx $dy]}
        } elseif {$action eq "align_parts"} {
            set mode [get $options alignment]
            if {$mode ni {left right top bottom center_x center_y} || [llength $rows] < 2} {error "对齐需要至少两个器件及有效的对齐方向。"}
            lassign [dict get [lindex $rows 0] box] l t r b
            foreach row $rows {
                lassign [dict get $row box] a c d e;set dx 0;set dy 0
                switch $mode {left {set dx [expr {$l-$a}]} right {set dx [expr {$r-$d}]} top {set dy [expr {$t-$c}]} bottom {set dy [expr {$b-$e}]} center_x {set dx [expr {int(round((($l+$r)-($a+$d))/20.0))*10}]} center_y {set dy [expr {int(round((($t+$b)-($c+$e))/20.0))*10}]}}
                dict set translations [dict get $row id] [list $dx $dy]
            }
        } elseif {$action eq "distribute_parts"} {
            set axis [get $options axis];if {$axis ni {horizontal vertical} || [llength $rows] < 3} {error "等距分布需要至少三个器件及水平或垂直方向。"}
            set slot [expr {$axis eq "horizontal" ? 0 : 1}];set ordered {}
            foreach row $rows {lappend ordered [list [lindex [dict get $row box] $slot] $row]};set ordered [lsort -integer -index 0 $ordered]
            set cursor [lindex [dict get [lindex [lindex $ordered 0] 1] box] $slot]
            if {[dict exists $options gap_mil]} {set gap [expr {max(10,[commandPartMil $page [dict get $options gap_mil]])}]} else {
                set end [lindex [dict get [lindex [lindex $ordered end] 1] box] [expr {$slot+2}]];set sum 0
                foreach item $ordered {set box [dict get [lindex $item 1] box];incr sum [expr {[lindex $box [expr {$slot+2}]]-[lindex $box $slot]}]}
                set gap [expr {int(round(($end-$cursor-$sum)/double([llength $rows]-1)/10))*10}]
                if {$gap < 10} {error "器件之间没有足够的空隙用于等距分布。"}
            }
            foreach item $ordered {
                set row [lindex $item 1];set box [dict get $row box];set shift [expr {$cursor-[lindex $box $slot]}]
                dict set translations [dict get $row id] [expr {$slot == 0 ? [list $shift 0] : [list 0 $shift]}]
                incr cursor [expr {[lindex $box [expr {$slot+2}]]-[lindex $box $slot]+$gap}]
            }
        } elseif {$action eq "rotate_parts"} {
            if {[get $options angle_degrees] ni {-270 -180 -90 90 180 270}} {error "旋转角度须为90度的倍数。"}
        } elseif {$action eq "mirror_parts"} {
            if {[get $options axis] ni {horizontal vertical}} {error "镜像方向须为水平或垂直。"}
        } else {error "不支持的器件变换。"}
        commandValidateContext $context;set originals $rows;set changedWires $allWires;set changed 1
        foreach row $rows {
            set part [dict get $row object];set id [dict get $row id]
            if {$action eq "rotate_parts"} {reviewCheckStatus [$part SetRotation [expr {([dict get $row rotation]+[dict get $options angle_degrees]/90+8)%4}]]} elseif {$action eq "mirror_parts"} {
                # Capture mirror is boolean. The other local axis is mirror + 180 degrees.
                set rotation [dict get $row rotation]
                set horizontal [expr {[dict get $options axis] eq "horizontal"}]
                if {$horizontal == ($rotation%2)} {reviewCheckStatus [$part SetRotation [expr {($rotation+2)%4}]]}
                reviewCheckStatus [$part SetMirror [expr {![dict get $row mirror]}]]
                # A 180-degree native rotation also shifts the symbol's bounding box.
                # Keep its visual center fixed for either world-axis reflection.
                lassign [dict get $row box] l t r b
                lassign [commandPartBox $part $state] a c d e
                lassign [commandXY [$part GetLocation $state]] x y
                commandPartLocation $part [list [expr {$x+($l+$r-$a-$d)/2}] [expr {$y+($t+$b-$c-$e)/2}]]
            } else {lassign [dict get $translations $id] dx dy;lassign [dict get $row location] x y;commandPartLocation $part [list [expr {$x+$dx}] [expr {$y+$dy}]]}
        }
        foreach cluster $clusters {
            lassign $cluster subset wires bounds;set id [dict get [lindex $subset 0] id]
            if {![dict exists $translations $id]} {continue}
            lassign [dict get $translations $id] dx dy
            foreach wire $wires {commandPartShiftWire $wire $dx $dy}
        }
        set boxes [commandObjects $page $exclude];set size [$page GetDocUnits]
        try {set pw [DboTclHelper_sGetCSizeX $size];set ph [DboTclHelper_sGetCSizeY $size]} finally {DboTclHelper_sDeleteCSize $size}
        set placed {}
        foreach cluster $clusters {
            lassign $cluster subset wires bounds;set points {}
            foreach row $subset {lassign [commandPartBox [dict get $row object] $state] l t r b;lappend points [list $l $t] [list $r $b]}
            if {[llength $wires]} {lassign [dict get $translations [dict get [lindex $subset 0] id]] dx dy;lassign $bounds l t r b;lappend points [list [expr {$l+$dx}] [expr {$t+$dy}]] [list [expr {$r+$dx}] [expr {$b+$dy}]]}
            lassign [commandBounds $points] l t r b
            if {![commandFits [concat $boxes $placed] $pw $ph $l $t [expr {$r-$l}] [expr {$b-$t}] 5]} {error "目标位置与已有图元重叠或超出图纸，已恢复原位置。"}
            lappend placed [list $l $t $r $b]
        }
        reviewCheckStatus [$page MarkModified];set after [commandPartModel $context]
        if {[commandPartLogical $before] ne [commandPartLogical $after]} {error "器件变换改变了引脚连接，已恢复原状态。"}
        set ::xiaokai::drc::commandFocus [dict create design $design page $page ids $ids]
        commandRevealParts $context $ids $state
    } on error {msg opts} {
        if {$changed} {
            if {[catch {
                foreach row $originals {set part [commandPartById $page [dict get $row id] $state];reviewCheckStatus [$part SetRotation [dict get $row rotation]];reviewCheckStatus [$part SetMirror [dict get $row mirror]];commandPartLocation $part [dict get $row location]}
                foreach wire $changedWires {commandPartRestoreWire $page $wire $state}
                if {[commandPartLogical [commandPartModel $context]] ne [commandPartLogical $before]} {error "恢复后的连接检查不一致"}
            } rollback]} {append msg " 恢复失败：[commandError $rollback]"}
        }
        return -options $opts $msg
    } finally {$state -delete}
    set verb [dict get {move_parts 移动 rotate_parts 旋转 mirror_parts 镜像 align_parts 对齐 distribute_parts 等距排列} $action]
    return "已$verb [llength $rows] 个器件：[join [lmap r $rows {dict get $r ref}] {、}]。随动 [llength $allWires] 条独立引线；位号、参数和引脚连接已复查。"
}
proc ::xiaokai::drc::commandEditPartData {context action options} {
    variable commandPartPropertyNames
    set state [DboState];set page [dict get $context page];set design [dict get $context design];set done {}
    try {
        set rows [commandPartTargets $context $options $state];set before [snapshot $design]
        if {$action eq "rename_parts"} {
            set values [get $options references {}];set used [commandPartRefs $before];set targets [lmap r $rows {string toupper [dict get $r occurrence_ref]}]
            if {[llength $values] != [llength $rows]} {error "新位号数量与器件数量不一致。"}
            set reserved {}
            foreach value $values row $rows {
                set key [string toupper $value]
                if {![regexp {^[A-Za-z_]+[1-9][0-9]*$} $value] || [dict exists $reserved $key] || ([dict exists $used $key] && ![string equal -nocase $value [dict get $row occurrence_ref]])} {error "位号 $value 无效或已被使用，本次未改名。"}
                dict set reserved $key 1
            }
        } else {
            set property [get $options property];set values [get $options values {}]
            if {$property ni $commandPartPropertyNames || [llength $values] ni [list 1 [llength $rows]]} {error "器件属性或对应值数量无效。"}
            foreach value $values {if {[string length $value] > 256 || [regexp {[\x00-\x1f]} $value] || ($property eq "Value" && [string trim $value] eq "")} {error "属性值为空、过长或包含控制字符。"}}
            if {[llength $values] == 1} {set values [lrepeat [llength $rows] [lindex $values 0]]}
        }
        commandValidateContext $context
        foreach row $rows value $values {
            set part [dict get $row object];set actor [dict get $row actor]
            if {$action eq "rename_parts"} {
                lappend done [list $row {} {}]
                commandPartReference $part $value;commandPartReference $actor $value
                if {![string equal -nocase $value [cstring $actor GetReference]]} {error "器件位号写入回读不一致。"}
            } else {
                lappend done [list $row $property [commandPartProperty $actor $property]]
                commandWritePartProperty $actor $property $value
            }
        }
        reviewCheckStatus [$page MarkModified]
        if {[commandPartLogical [commandPartModel $context]] ne [commandPartLogical $before]} {error "属性修改影响了引脚连接，已停止并恢复。"}
        set ::xiaokai::drc::commandFocus [dict create design $design page $page ids [lmap r $rows {dict get $r id}]]
    } on error {msg opts} {
        foreach item [lreverse $done] {
            lassign $item row key old
            if {[catch {
                if {$action eq "rename_parts"} {commandPartReference [dict get $row object] [dict get $row raw_ref];commandPartReference [dict get $row actor] [dict get $row occurrence_ref]} else {
                    lassign $old exists value
                    if {$exists} {commandWritePartProperty [dict get $row actor] $key $value} else {set k [DboTclHelper_sMakeCString $key];try {reviewCheckStatus [[dict get $row actor] DeleteUserProp $k]} finally {DboTclHelper_sDeleteCString $k}}
                }
            } rollback]} {append msg " 属性恢复失败：[commandError $rollback]"}
        }
        if {[llength $done]} {catch {commandPartModel $context}}
        return -options $opts $msg
    } finally {$state -delete}
    if {$action eq "rename_parts"} {return "已将器件位号依次改为[join $values {、}]，并复查引脚连接。"}
    return "已修改 [llength $rows] 个器件的 $property：[join [lmap r $rows {dict get $r ref}] {、}]。实际属性与引脚连接已复查。"
}
