# Read-only connection facts. Native flat-net identity, never a displayed name,
# joins endpoints across hierarchy occurrences. No native handles go to the API.
namespace eval ::xiaokai::drc {
    variable connectionSnapshot {}
    variable connectionChecked {}
    variable connectionRows {}
    variable connectionStatus "实际连接引脚；双击定位。"
}
proc ::xiaokai::drc::connectionModel {checked} {
    variable connectionSnapshot; variable connectionChecked
    if {[resultState $checked] ne "current"} {error "请切回本次设计；工程变化后需重新检查。"}
    if {$connectionChecked ne $checked || ![dict exists $connectionSnapshot pins]} {
        set model [snapshot [dict get $checked design]]
        if {[resultState $checked] ne "current"} {error "读取期间工程已变化，请重新检查。"}
        set connectionSnapshot $model; set connectionChecked $checked
    }
    return $connectionSnapshot
}
proc ::xiaokai::drc::connectionFacts {row model} {
    set groups {}; set missing {}; set related {}; set parts {}
    foreach pin [get $row _targets {}] {
        lappend parts [list [get $pin hierarchy_path] [get $pin _part_id]]
        set flat [get $pin flat_net]
        if {$flat eq ""} {lappend missing $pin; continue}
        if {![dict exists $groups $flat]} {
            dict set groups $flat [dict create name [get $pin net_name] endpoints {}]
        }
    }
    set seen {}
    foreach pin [dict get $model pins] {
        set flat [get $pin flat_net]
        if {[list [get $pin hierarchy_path] [get $pin _part_id]] in $parts} {lappend related $pin}
        if {$flat eq "" || ![dict exists $groups $flat] || ![get $pin is_primitive 1]} {continue}
        set key [list [get $pin hierarchy_path] [get $pin schematic] [get $pin sheet_name] \
            [get $pin refdes] [get $pin _part_id] [get $pin _pin_id] [get $pin pin_number]]
        if {[dict exists $seen $key]} {continue}
        dict set seen $key 1
        set group [dict get $groups $flat]; dict lappend group endpoints $pin
        dict set groups $flat $group
    }
    # Drop the native identity keys before returning serialized candidates.
    return [dict create networks [dict values $groups] unresolved $missing related $related]
}
proc ::xiaokai::drc::connectionRender {row checked} {
    variable connectionRows; variable connectionStatus
    set tree .xiaokaiDrc.tabs.review.connections.tree
    if {![winfo exists $tree]} {return}
    $tree delete [$tree children {}]; set connectionRows {}
    if {[catch {set facts [connectionFacts $row [connectionModel $checked]]} msg]} {
        set connectionStatus "连接读取未完成：$msg"; return
    }
    set index 0; set groupIndex 0
    foreach network [dict get $facts networks] {
        incr groupIndex
        foreach pin [dict get $network endpoints] {
            set id c[incr index]; dict set connectionRows $id $pin
            $tree insert {} end -id $id -values [list "[get $network name {未命名}] (#$groupIndex)" \
                [get $pin refdes] "[get $pin pin_number] ([get $pin pin_name])" \
                "[get $pin hierarchy_path] · [get $pin schematic]/[get $pin sheet_name]"]
        }
    }
    foreach pin [dict get $facts unresolved] {
        set id c[incr index]; dict set connectionRows $id $pin
        $tree insert {} end -id $id -values [list {网络未解析} [get $pin refdes] \
            "[get $pin pin_number] ([get $pin pin_name])" "[get $pin hierarchy_path] · [get $pin schematic]/[get $pin sheet_name]"]
    }
    set connectionStatus "原生网络连接：$groupIndex 个网络，$index 个引脚条目；双击定位。"
    if {[llength [dict get $facts unresolved]]} {append connectionStatus " 未解析项仅显示目标脚，不推测对端。"}
    if {!$index} {set connectionStatus "未解析到器件引脚端点；保留原生诊断，不按网名猜测连接。"}
}
proc ::xiaokai::drc::connectionClick {x y} {
    variable connectionRows; variable reviewPreview
    set tree .xiaokaiDrc.tabs.review.connections.tree
    set id [$tree identify row $x $y]
    if {![dict exists $connectionRows $id]} {return}
    $tree selection set $id
    after idle [list ::xiaokai::drc::connectionLocate [dict get $connectionRows $id] $reviewPreview]
}
proc ::xiaokai::drc::connectionLocate {pin checked} {
    variable connectionStatus; variable reviewPreview
    if {[catch {
        if {$reviewPreview ne $checked || [resultState $checked] ne "current"} {error "工程或检查批次已变化，请重新检查后定位。"}
        set row [dict create hierarchy_path [get $pin hierarchy_path] _schematic [get $pin schematic] \
            sheet_name [get $pin sheet_name] refdes [get $pin refdes] _targets [list $pin] _pin_specific 1]
        if {[get $pin _pin_point] ne ""} {dict set row _focus_point [dict get $pin _pin_point]}
        locate $row $checked
    } msg]} {set connectionStatus $msg; return}
    set connectionStatus "已定位 [get $pin hierarchy_path] · [get $pin refdes] 的 [get $pin pin_number] 脚。"
}
