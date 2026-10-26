# SPDX-License-Identifier: GPL-3.0-only
namespace eval ::xiaokai::textaffix {
    variable version 1.0.0
}

proc ::xiaokai::textaffix::appendText {value text side {removeExisting 1}} {
    if {$text eq ""} {error "请先输入要添加的文字。"}
    if {$side ni {before after}} {error "请选择添加到现有文字之前或之后。"}
    if {$removeExisting && (($side eq "before" && [string first $text $value] == 0)
        || ($side eq "after" && [string length $value] >= [string length $text]
        && [string range $value end-[expr {[string length $text]-1}] end] eq $text))} {
        if {$side eq "before"} {return [string range $value [string length $text] end]}
        return [string range $value 0 end-[string length $text]]
    }
    if {$side eq "before"} {return $text$value}
    return $value$text
}

proc ::xiaokai::textaffix::makePlan {rows text side removeExisting} {
    set plan {}; set seen {}
    foreach row $rows {
        set key [dict get $row key]
        if {[dict exists $seen $key]} {continue}
        dict set seen $key 1
        set old [dict get $row value]
        set new [appendText $old $text $side $removeExisting]
        if {$old eq $new} {continue}
        dict set row before $old
        dict set row after $new
        lappend plan $row
    }
    return $plan
}
