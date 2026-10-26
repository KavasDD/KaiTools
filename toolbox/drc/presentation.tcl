# SPDX-License-Identifier: GPL-3.0-only
# User-facing descriptions and grouping. Native rule decisions remain unchanged.
proc ::xiaokai::drc::explain {row} {
    if {[dict exists $row _related]} {
        set descriptions {}; set fixes {}; set first {}
        foreach original [dict get $row _related] {
            set desc [explain $original]
            if {$first eq ""} {set first $desc}
            lappend descriptions [dict get $desc explanation]
            lappend fixes [dict get $desc suggestion]
        }
        dict set first explanation [join [lsort -unique $descriptions] \n]
        dict set first suggestion [join [lsort -unique $fixes] \n]
        dict set first title "[dict get $first title]（关联 DRC / 网表）"
        dict set first summary "[dict get $first summary]（DRC / 网表）"
        return $first
    }
    set id [get $row rule_id]; set net [get $row net_name]; set ref [get $row refdes]
    if {$ref eq ""} {set ref "此器件"}
    set object [expr {$net ne "" ? "网络 $net" : ($ref ne "" ? $ref : "此位置")}]
    set kind $id
    switch $id {
        single_node_nets {set title "网络只有一个连接点"; set why "$object 只有一个有效连接点。"; set fix "检查漏接、断线和网络名。若为有意保留的电源单点，可配置白名单。"}
        unconnected_pin {set title "引脚未连接"; set why "[pinLabel $row]未连接。"; set fix "确认导线端点接到引脚；若有意悬空，使用原生 No Connect 标记。"}
        drive_source_pin_conflict {
            if {[regexp -nocase {no driving|no driver|not driven|without.*driv} [get $row message]]} {
                set kind no_driver; set title "输入网络没有驱动源"; set why "$object 上的输入引脚没有找到有效驱动。"; set fix "检查输出端、层次端口方向及引脚电气类型。"
            } else {
                set kind pin_conflict; set title "引脚电气类型冲突"; set why "$object 的连接不符合当前 ERC 类型矩阵。"; set fix "检查是否存在多个输出直接相连，核对引脚和端口的电气类型。"
            }
        }
        duplicate_net_name {set title "网络名称冲突"; set why "$object 存在原生 DRC 识别的重名冲突。"; set fix "核对全局名称、网络别名及层次范围；合法相连的同名网络无需改名。"}
        hier_port_conn {set title "层次端口不匹配"; set why "分层 block 与子图端口的名称、方向或连接不匹配。"; set fix "核对当前实例的 block 引脚和子图端口，注意复用实例的连接。"}
        unconnected_bus {set title "总线未有效连接"; set why "总线缺少有效连线或成员引脚连接。"; set fix "核对总线成员、分支入口和成员网络名。"}
        power_pin_visibility {set title "电源脚显示定义不一致"; set why "$ref 的电源脚可见性与符号定义不一致。"; set fix "对照库符号和设计缓存，核对电源脚显示设置。"}
        convert_view_sync {set title "符号两种视图引脚不一致"; set why "$ref 的 Normal 与 Convert 视图引脚定义不一致。"; set fix "在库编辑器核对两种视图的引脚编号、名称和类型。"}
        pin_group_assign {set title "引脚分组设置不正确"; set why "$ref 的 Pin Group 分配不符合原生要求。"; set fix "核对分组中的引脚类型和组分配。"}
        missing_pin_num {set title "引脚编号缺失"; set why "$ref 存在未填写编号的引脚。"; set fix "在符号定义中补全 Pin Number，并核对设计缓存。"}
        name_prop_consistency {set title "名称属性不一致"; set why "层次 block 的名称属性与其定义不一致。"; set fix "对照原生详细信息核对 block 名称和对应子图属性。"}
        netlist_error {
            set title "网表输出错误"
            set kind netlist_error
            set why "Capture 原生 PCB 网表输出发现错误。"
            set fix "查看原生详细信息，按错误提示核对器件和网表属性。"
            set message [get $row message]
            if {[regexp -nocase {footprint|JEDEC_TYPE} $message]} {
                set title "网表中的封装属性有误"; set kind netlist_footprint
                set why "$ref 的封装属性使网表无法正常输出。"
                set fix "按原生网表提示补全或修正 PCB Footprint；这是网表引擎返回的错误。"
            } elseif {[regexp -nocase {duplicate.*pin|pin.*duplicat} $message]} {
                set title "网表引脚编号重复"; set kind netlist_duplicate_pin
                set why "$ref 的网表引脚编号存在重复。"
                set fix "核对符号引脚编号与器件封装定义。"
            } elseif {[regexp -nocase {illegal|invalid} $message]} {
                set title "网表属性格式不正确"; set kind netlist_invalid
                set why "网表引擎发现不符合要求的名称或属性。"
            } elseif {[regexp {^网表输出未完成：} $message]} {
                set title "网表未能输出"; set kind netlist_failed
                set why $message
            }
        }
        "" {set title "原生检查发现问题"; set why "Capture 原生检查报告了此问题，当前版本尚未识别其分类。"; set fix "查看原生详细信息，核对提示的连接或符号属性。"}
        default {error "Unknown rule: $id"}
    }
    # Common-cause group titles stay short; concrete child rows carry objects.
    set summary $title
    if {$id eq "unconnected_pin"} {set summary "[pinLabel $row]未连接"} elseif {$net ne "" && $kind eq "no_driver"} {
        set summary "网络 $net 没有驱动源"
    } elseif {$net ne "" && $id eq "single_node_nets"} {
        set summary "网络 $net 只有一个连接点"
    } elseif {[get $row refdes] ne ""} {set summary "[get $row refdes]：$title"} elseif {$net ne ""} {set summary "网络 $net：$title"}
    return [dict create kind $kind title $title summary $summary explanation $why suggestion $fix]
}
proc ::xiaokai::drc::pinLabel {row} {
    set labels {}
    foreach pin [get $row _targets {}] {
        set number [get $pin pin_number [get $pin pin_name]]
        if {$number eq ""} {set number [get $pin pin_name]}
        if {$number ne ""} {lappend labels "[get $pin refdes] 的 $number 脚"}
    }
    if {[llength $labels]} {return [join [lsort -unique $labels] {、}]}
    set ref [get $row refdes]
    set pin [get $row pin_info]
    if {$ref ne "" && $pin ne ""} {return "$ref 的 $pin 脚"}
    if {$ref ne ""} {return "$ref 的引脚"}
    return "此引脚"
}
proc ::xiaokai::drc::canLocate {row} {
    if {[get $row _schematic] eq "" || [get $row sheet_name] eq "" || [get $row hierarchy_path] eq ""} {return 0}
    if {[get $row _focus_point] ne ""} {return 1}
    foreach pin [get $row _targets {}] {if {[get $pin _part_id] ne "" || [get $pin _pin_id] ne ""} {return 1}}
    return [regexp {\(([-0-9.]+),\s*([-0-9.]+)\)} [get $row message]]
}
proc ::xiaokai::drc::locationKey {row} {
    set path [get $row hierarchy_path]; set sheet [get $row sheet_name]
    if {$path eq "" || $sheet eq ""} {return ""}
    set prefix [list [string tolower $path] [string tolower $sheet]]
    # Native diagnostic coordinates identify the same point across engines.
    if {[regexp {\(([-0-9.]+),\s*([-0-9.]+)\)} [get $row message] -> x y]} {
        return [list {*}$prefix point [format %.4f $x] [format %.4f $y] [string tolower [get $row refdes]]]
    }
    set parts {}; set pins {}
    foreach target [get $row _targets {}] {
        if {[get $target _part_id] ne ""} {lappend parts [dict get $target _part_id]}
        if {[get $target _pin_id] ne ""} {lappend pins [dict get $target _pin_id]}
    }
    set parts [lsort -unique $parts]; set pins [lsort -unique $pins]
    if {[llength $parts] != 1} {return ""}
    if {[get $row _pin_specific 0]} {
        if {[llength $pins] != 1} {return ""}
        return [list {*}$prefix pin $parts $pins]
    }
    return [list {*}$prefix part $parts]
}
proc ::xiaokai::drc::relatedRows {rows} {
    set buckets {}; set order {}; set i 0
    foreach row $rows {
        set key [locationKey $row]
        if {$key eq ""} {set key [list unknown [incr i]]}
        if {![dict exists $buckets $key]} {lappend order $key}
        dict lappend buckets $key $row
    }
    set result {}
    foreach key $order {
        set entries [dict get $buckets $key]; set drc 0; set netlist 0
        foreach entry $entries {
            if {[get $entry rule_id] eq "netlist_error"} {set netlist 1} else {set drc 1}
        }
        if {!$drc || !$netlist} {lappend result {*}$entries; continue}
        # Preserve all original rows for details/export. The primary DRC row
        # retains its rule fields; the native allowlist is unchanged.
        foreach entry $entries {if {[get $entry rule_id] ne "netlist_error"} {set merged $entry; break}}
        set messages {}; set targets {}
        foreach entry $entries {
            set source [expr {[get $entry rule_id] eq "netlist_error" ? "网表" : "DRC"}]
            set message "【$source】[get $entry message]"
            if {$message ni $messages} {lappend messages $message}
            foreach target [get $entry _targets {}] {if {$target ni $targets} {lappend targets $target}}
        }
        dict set merged _related $entries
        dict set merged message [join $messages \n\n]
        # Use the primary exact pin when present, otherwise component targets.
        if {![get $merged _pin_specific 0]} {dict set merged _targets $targets}
        lappend result $merged
    }
    return $result
}
proc ::xiaokai::drc::groupRows {rows {query ""}} {
    set grouped {}; set seen {}
    foreach row $rows {
        set desc [explain $row]
        if {$query ne "" && [string first [string tolower $query] [string tolower "$row $desc"]] < 0} {continue}
        # Deduplicate exact native occurrences, never merge different instances.
        set signature [list [get $row rule_id] [get $row hierarchy_path] [get $row sheet_name] [get $row message]]
        if {[dict exists $seen $signature]} {continue}
        dict set seen $signature 1
        set kind [dict get $desc kind]
        # Multiple affected inputs on one net share one parent problem.
        set cause [list [get $row hierarchy_path] [get $row sheet_name] [get $row net_name]]
        if {[get $row net_name] eq ""} {set cause [list [get $row hierarchy_path] [get $row sheet_name] [get $row refdes]]}
        if {[get $row rule_id] eq "netlist_error"} {
            # Aggregate common native netlist errors by message code.
            set cause $kind
            if {[regexp {\(([^)]+)\)} [get $row message] -> code]} {set cause $code}
        } elseif {$kind ni {no_driver pin_conflict single_node_nets unconnected_pin}} {set cause $signature}
        dict lappend grouped [list $kind $cause] $row
    }
    return $grouped
}
