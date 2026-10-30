# Persisted naming objects are distinct from the electrical net's preferred name.
proc ::xiaokai::drc::commandNetLabels {page {wires {}}} {
    set fullScan [expr {$wires eq ""}]
    if {$fullScan} {set wires [commandWires $page]}
    set state [DboState];set result {};set wireIds {}
    try {
        foreach row $wires {
            foreach item [dict get $row aliases] {
                set alias [lindex $item 0]
                lappend result [dict create id [lindex $item 3] object $alias kind alias name [lindex $item 2] point [lindex $item 1] wire_id [dict get $row id]]
            }
            foreach off [dict get $row connectors] {
                set id [dict get $off id]
                dict set wireIds $id [dict get $row id]
                lappend result [dict create id $id object [dict get $off object] kind offpage name [dict get $off name] point [dict get $off hot] wire_id [dict get $row id]]
            }
        }
        if {!$fullScan} {return $result}
        set it [$page NewOffPageConnectorsIter $state]
        try {
            for {set off [$it NextOffPageConnector $state]} {$off ne "NULL"} {set off [$it NextOffPageConnector $state]} {
                set id [$off GetId $state]
                if {[dict exists $wireIds $id]} {continue}
                lappend result [dict create id $id object $off kind offpage name [cstring $off GetName] point [commandXY [$off GetOffsetHotSpot $state]] wire_id [get $wireIds $id -1]]
            }
        } finally {delete_DboPageOffPageConnectorsIter $it}
        return $result
    } finally {$state -delete}
}
proc ::xiaokai::drc::commandPinPartition {model} {
    set groups {};set pins {}
    foreach pin [dict get $model pins] {
        if {![get $pin is_primitive 1]} {continue}
        set identity [list [get $pin hierarchy_path] [get $pin schematic] [get $pin sheet_name] [get $pin _part_id] [get $pin _pin_id] [get $pin pin_number]]
        lappend pins [list $identity [get $pin refdes] [get $pin _pin_point] [get $pin no_connect] [get $pin pin_type]]
        set flat [get $pin flat_net]
        if {$flat ne ""} {dict lappend groups $flat $identity}
    }
    set partitions {};dict for {net members} $groups {lappend partitions [lsort $members]}
    return [list [lsort $pins] [lsort $partitions]]
}
proc ::xiaokai::drc::commandSetLabelName {object name} {
    set value [DboTclHelper_sMakeCString $name]
    try {
        reviewCheckStatus [$object SetName $value]
        if {[cstring $object GetName] ne $name} {error "网络名称写入回读不一致。"}
    } finally {DboTclHelper_sDeleteCString $value}
}
proc ::xiaokai::drc::commandRenameNetLabels {context encodedOptions encodedNames} {
    package require json
    set options [json::json2dict [aiDecode $encodedOptions]]
    set indices [get $options label_indices {}];set names [split $encodedNames \n];set labels [dict get $context labels]
    if {[llength $indices] < 1 || [llength $indices] > 32 || [llength $indices] != [llength $names] || [llength [lsort -unique $indices]] != [llength $indices]} {error "请指定1～32个名称标签及对应新名称。"}
    set mapping {};set state [DboState];set design [dict get $context design];set page [dict get $context page]
    set schema [$page GetOwner];set changes {};set done {};set pages {};set summary {}
    try {
        foreach index $indices name $names {
            if {![string is integer -strict $index] || $index < 0 || $index >= [llength $labels] || ![regexp {^[A-Za-z_][A-Za-z0-9_+.-]{0,63}$} $name]} {error "名称标签索引或新网名无效。"}
            set label [lindex $labels $index];set old [dict get $label name];set key [string tolower $old]
            if {[dict get $label wire_id] == -1} {error "目标连接符没有接入导线，请先核对连接。"}
            if {[dict exists $mapping $key] && [dict get $mapping $key] ne $name} {error "同一旧网名不能改成多个新名称。"}
            dict set mapping $key $name
            if {$old ne $name} {lappend summary "$old → $name"}
        }
        if {![llength $summary]} {return "所选名称已符合要求，无需修改。"}
        if {[llength [lsort -unique -nocase [dict values $mapping]]] != [dict size $mapping]} {error "多个不同网名不能合并成同一名称。"}
        set before [snapshot $design];set schemaName [cstring $schema GetName];set uses 0
        foreach item [dict get $before contexts] {if {[dict get $item schematic] eq $schemaName} {incr uses}}
        if {$uses != 1} {error "目标位于复用或未实例化的分层图纸，需明确实例后才能改名。"}
        set partition [commandPinPartition $before]
        set views [$design NewViewsIter $state $::IterDefs_SCHEMATICS]
        try {
            for {set view [$views NextView $state]} {$view ne "NULL"} {set view [$views NextView $state]} {
                set sch [DboViewToDboSchematic $view];set iterator [$sch NewPagesIter $state]
                try {
                    for {set p [$iterator NextPage $state]} {$p ne "NULL"} {set p [$iterator NextPage $state]} {
                        set all [commandNetLabels $p];set targetSchema [expr {[cstring $sch GetName] eq $schemaName}]
                        # Power and hierarchical ports need a separate coordinated
                        # rename. Include them in collision checks, never edit them.
                        foreach spec {{NewGlobalsIter NextGlobal delete_DboPageGlobalsIter} {NewPortsIter NextPort delete_DboPagePortsIter}} {
                            lassign $spec maker next cleanup;set it [$p $maker $state]
                            try {
                                for {set object [$it $next $state]} {$object ne "NULL"} {set object [$it $next $state]} {lappend all [dict create object $object kind protected name [cstring $object GetName]]}
                            } finally {$cleanup $it}
                        }
                        foreach label $all {
                            set actual [dict get $label name];set key [string tolower $actual]
                            dict for {old replacement} $mapping {
                                if {[string equal -nocase $actual $replacement] && $key ne $old} {error "新网名 $replacement 已存在，可能合并网络；本次未修改。"}
                            }
                            if {!$targetSchema || ![dict exists $mapping $key]} {continue}
                            if {[dict get $label kind] eq "protected"} {error "旧网名涉及电源或分层端口，需同步处理端口；本次未修改。"}
                            set next [dict get $mapping $key]
                            if {$actual ne $next} {lappend changes [list [dict get $label object] $actual $next $p]}
                        }
                    }
                } finally {delete_DboSchematicPagesIter $iterator}
            }
        } finally {delete_DboLibViewsIter $views}
        # Unlabelled existing networks also participate in collision detection.
        foreach pin [dict get $before pins] {
            foreach actual [list [get $pin net_name] [get $pin local_net]] {
                dict for {old replacement} $mapping {if {[string equal -nocase $actual $replacement] && ![dict exists $mapping [string tolower $actual]]} {error "新网名 $replacement 已被器件网络使用，本次未修改。"}}
            }
        }
        commandValidateContext $context
        foreach change $changes {
            lassign $change object old next p;lappend done $change
            if {$p ni $pages} {lappend pages $p}
            commandSetLabelName $object $next
        }
        foreach p $pages {reviewCheckStatus [$p MarkModified];DboTclHelper_sEvalPage $p}
        snapshot $design
        if {[commandPinPartition [snapshot $design]] ne $partition} {error "改名后器件引脚连接分组发生变化，已停止并恢复名称。"}
    } on error {msg opts} {
        foreach change [lreverse $done] {
            if {[catch {commandSetLabelName [lindex $change 0] [lindex $change 1]} rollback]} {append msg " 名称恢复失败：[commandError $rollback]"}
        }
        if {[llength $done]} {
            if {[catch {
                foreach p $pages {DboTclHelper_sEvalPage $p}
                snapshot $design
                if {[commandPinPartition [snapshot $design]] ne $partition} {error "引脚连接分组未恢复"}
            } rollback]} {append msg " 恢复后连接复查失败：[commandError $rollback]"}
        }
        return -options $opts $msg
    } finally {$state -delete}
    return "已修改[join [lsort -unique $summary] {；}]。同步同一原理图内 [llength $changes] 个同名标签（[llength $pages] 页），其余别名保留；引脚连接分组已复查。"
}
