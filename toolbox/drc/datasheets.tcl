proc ::xiaokai::drc::datasheetInfo {} {
    set rows {}
    if {[winfo exists .xiaokaiDrc.tabs.review.tree] && [.xiaokaiDrc.tabs select] eq ".xiaokaiDrc.tabs.review"} {
        set id [reviewSelected]
        if {[dict exists $::xiaokai::drc::reviewItems $id row]} {set rows [list [dict get $::xiaokai::drc::reviewItems $id row]]}
    }
    if {![llength $rows] && [winfo exists .xiaokaiDrc.list.tree]} {set rows [selectedRows]}
    set components {}
    foreach row $rows {
        foreach pin [get $row _targets {}] {
            if {[get $pin part_number] eq ""} {continue}
            dict set components [list [get $pin hierarchy_path] [get $pin _part_id]] $pin
        }
    }
    if {[dict size $components] == 1} {
        if {![refreshFreshness $::xiaokai::drc::result]} {error "工程已变化，请重新检查后查看该项手册。"}
        return [lindex [dict values $components] 0]
    }
    # Also works directly from a selected schematic part, without any DRC item.
    if {[llength [info commands GetSelectedObjects]]} {
        set selected [GetSelectedObjects]
        if {[llength $selected] == 1 && [[lindex $selected 0] GetObjectType] == $::DboBaseObject_PART_INSTANCE &&
            ![catch {DboBaseObjectToDboPartInst [lindex $selected 0]} inst] && $inst ne "NULL"} {
            set info [componentInfo $inst $inst]
            dict set info refdes [cstring $inst GetReference]
            return $info
        }
    }
    error "请选中一个器件，或列表中的具体问题，再查看手册。"
}
proc ::xiaokai::drc::datasheetShow {} {
    # Capture the source selection before switching away from AI review.
    datasheetAction read
    uiTab datasheet
}
